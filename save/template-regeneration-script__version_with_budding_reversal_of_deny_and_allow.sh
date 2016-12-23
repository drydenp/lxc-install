#!/bin/bash

while [ $# -gt 0 ]; do
	case "$1" in
		remove) remove=yes; shift; ;;
		-v)     verbose=yes; shift; ;;
		*)      shift; # just ignore
	esac
done

# Main ethernet device.

eth0=eth0

# I create two virtual devices to hold IP addresses for us.

# Ideally I would use a real different name. However this is not supported
# by anything it seems. Logically I want to separate the two interfaces into
# two devices, or the two aliases in two interfaces, which means the same thing here.

alias0="${eth0}:0"
alias1="${eth0}:1"
base0="${alias0%:*}"
base1="${alias0%:*}"

# Iptables will not work on aliassed devices. So in our rules we cannot actually
# have them.

# Ideally base0 and base1 are allowed to be different, but this is not my usecase.

# This specific solution is based on a single ethernet device (that can be virtual as well, as in a container).

# (Or as in a virtualized environment such as on a VPS host).

# Just obtain the primary IP from the first alias. This won't work if it does not
# yet exist! In that case we must derive it from base0, but this is not covered yet.

primary_ip=$(ip addr show dev $base0 | grep "inet .* $alias0$" | head -1 | awk '{print $2'} | sed "s@/..@@")

# Just assume a normal gateway address.

primary_gateway=${primary_ip%.*}.1

# In our firewall rules, since base1 is the "device" of the external IP address
# that leads to our container(s) it will hold most of the firewall rules.

secondary_ip={SECONDARY_IP}   # <-- this is a template value replaced by something actual
secondary_gateway=${secondary_ip%.*}.1

# We name our bridge lxc-nat-bridge. lxcbr0 is also possible.

lxc=lxc-nat-bridge
lxc_sub={LXC_SUB}/24    # <-- a subnet of just 254 hosts should be enough. Right.
                        # <-- I mean how many containers do you want actually.
						# <-- You can increase this (ie. 16 or 20 or something like that.

internal_ip=${lxc_sub%.0/*}.1   # <-- we take the first IP

container_ip=${lxc_sub%.0/*}.2  # <-- our (only) container gets the second.

								# <-- You could place anything on that network with proper routing.

# SECONDARY_IP and LXC_SUB are substituted using a template file.

# The resulting file can generate /etc/network/interfaces directly.

# ---------------------------------------------------------------------------- #

   # My personal (DP) firewall is called Vuurmuur. It is not actively getting maintained.
   # It uses "conntrack" or "connmark" values. These values used are 0, 1 and 2 as distinct
   # values in a range. It assumes it is going to be alone. I break that assumption.

   # Regardless in general it could be wise to use a value that is out of range or ordinary
   # firewalls. This is why I use the value 32, which is the 6th bit (counting from 1).

   connmark=32

   # The code and this template are completely mixed. That is why I will indent the
   # code here.

   config_test() {
	   echo -n "Testing $1 for \"$2\"..."
	   cat "$1" | grep -F "$2" > /dev/null && {
		   cat "$1" | grep -Fx "$2" > /dev/null && {
			   echo " found"
		   } || { echo " found but possibly commented out."; return 2; }
	   } || {
		   echo " not found."
		   false
	   }
   }

   config_remove() {
	   echo -n "Removing \"$2\" from $1..."
	   tmp=$(mktemp)
	   cat "$1" | sed "\#$2#d" > $tmp
	   diff "$1" "$tmp" > /dev/null && {
		   echo " nothing removed."
		   rm $tmp
	   } || {
		   echo " removed."
		   mv $tmp "$1"
	   }
   }

   config_install() {
	   echo "Adding \"$2\" to $1"
	   echo "$2" >> "$1"
   }

   config_update() {
	   config_test "$1" "$2" || {
		   res=$?
		   [ $res -eq 2 ] && config_remove "$1" "$2"
		   config_install "$1" "$2"
	   }
   }
	
   echo
   
   # We'll perform a certain action based on the parameter (remove or install).
   
   [ ! $remove ] && {
	   config_do=config_update
   } || {
	   config_do=config_remove
   }

# ---------------------------------------------------------------------------- #

# I had not noticed, but this is some extra protection code in case your firewall
# doesn't work.

# It denies all traffic as INPUT on the secondary IP by first disallowing it and then
# granting it only to the primary IP.
   
$config_do /etc/hosts.deny "ALL @${secondary_ip}: ALL"
$config_do /etc/hosts.deny "nfsd, portmap @{primary_ip}: ALL"

# Localhost, IPv6 localhost, 10.x.x.x and 192.168.x.x are not denied anything.

$config_do /etc/hosts.allow "ALL EXCEPT nfsd portmap @${primary_ip}: ALL"

# The primary IP is allowed everything except nfs and the port mapper (2049 and 111)
# The UDP port mapper (sunrpc, or /sbin/rpcbind) are used for DDoS amplification.





   
   # The result is that the secondary IP cannot be used to host services by the host, but only by the
   # container(s). Just a protection measure to more clearly separate the systems from one another.
   
   $config_do /etc/iproute2/rt_tables "$(printf "2\tsecond")"      # create a name for the second table.
   
   [ $remove ] && exit            # exit now if you only removed stuff.
   
   echo
   [ $verbose ] && { asfollows=" as follows"; devnull=; } || { asfollows=; devnull="> /dev/null"; }
   
   echo "Recreating /etc/network/interfaces${asfollows}. Hope it works."
   [ $verbose ] && {
	   echo
	   echo "===================================================="
   }
   
# ---------------------------------------------------------------------------- #

# Below comes the interfaces file with excessive documentation, which I will prune.
   
   cat << EOF | eval tee /etc/network/interfaces $devnull
# This file describes the network interfaces available on your system
# and how to activate them. For more information, see interfaces(5).

source /etc/network/interfaces.d/*

auto lo $eth0 $alias0 $alias1 $lxc
allow-hotplug $alias0 $alias1

# The loopback network interface

iface lo inet loopback

iface $eth0 inet manual
  pre-up ip link set eth0 up
  #up echo 1 > /proc/sys/net/ipv6/conf/$eth0/disable_ipv6    # <-- uncomment to disable ipv6

iface $alias0 inet dhcp
  up echo 1 > /proc/sys/net/ipv4/ip_forward

iface $alias1 inet static
  address $secondary_ip
  netmask 255.255.255.0

  # We delay this interface until we have our first link ($alias0)

  pre-up count=0; while ! ip addr show dev $base0 | grep "inet .* $alias0$" && [ \$count -lt 10 ]; do sleep 0.5s; count=\$(( count+1 )); done

  # Since we use a secondary IP we *may* have a secondary gateway as well. Traffic incoming through
  # this gateway we will route back out through this gateway. This creates complications if our
  # LXC container needs to interface with other local (VPN) networks as well.

  # But for now we will say that we will have a secondary routing table with a different default
  # route.
  
  # To this end we shall create a "rule" to route traffic onto that gateway if the traffic is coming from:
  # - either our LXC
  # - or the external secondary IP itself ($secondary_ip).

  # To escape the condition that our traffic cannot be routed over VPN and the like, we will create
  # additional rules to cover this.

  # Currently I cover this in part by copying the main routing table after interface UP. This is annoying
  # to achieve for VPN itself and requires extra work. Therefore the copying is probably pointless and is
  # already covered by these additional rules (IP rules, not Firewall rules).

  # So there are really two options:
  # 1. Ensure the second routing table is always a near-copy of the first (main)
  # 2. Ensure we don't add any additional rules to our ruleset.

  # Originally I thought #2 would be cumbersome but in fact this doesn't happen at all, routing table
  # changes are much more frequent than ruleset changes.

  # This is the copying code that I will comment out here.

  # Note that traffic originating FROM THE SECOND IP is an anomaly that must be explicitly desired.
  # But this will surely happen if we rewrite our source packets (address) when required.

  # up ip route show | grep -v ^default | while read line; do ip route add \$line table second; done
  
  # The new default route for the second table:

  up ip route add default via $secondary_gateway dev $base1 table $second_table

  # The rule that ensures routing (rare occasion):

  up ip rule add from $secondary_ip lookup second
  down ip rule del from $secondary_ip lookup second

  down ip route flush table second

  # At this point we have not created the exceptions yet (for 10.0.0.0 / 192.168.0.0) but
  # our LXC is not up yet.



iface $lxc inet static
  bridge_ports none
  bridge_fd 0
  address $internal_ip
  netmask 255.255.255.0            # <-- if you need more addresses, fix this.

  # Another waiting event:

  pre-up count=0; while ! ip addr show dev $base1 | grep "inet .* $alias1$" && [ \$count -lt 10 ]; do sleep 0.5s; count=\$(( count+1 )); done           # <-- decimal sleep is not possible on some systems

  # up echo 1 > /proc/sys/net/ipv6/conf/$lxc/disable_ipv6     # <-- uncomment if required
 
  # Earlier update of the second routing table:

  # up ip route show | grep "^$lxc_sub" | { read line; ip route add \$line table second; }

  # Now the real rules that are very much required:

  up ip rule add from $lxc_sub lookup second                  # <-- default route for $lxc
  up ip rule add from all to 10.0.0.0/8 lookup main           # <-- other stuff uses
  up ip rule add from all to 192.168.0.0/16 lookup main       # <-- the main table

  # These are just some sample rules you can use if you don't want external traffic to be
  # routed over your VPN or similar. And if your default policy is drop:

  up iptables -P FORWARD DROP
  up iptables -A FORWARD -i $base1 -o $lxc -j ACCEPT   # from $secondary_ip to $container_ip
  up iptables -A FORWARD -i $base1 -j DROP             # from $secondary_ip to everything else.
  up iptables -I FORWARD -i $lxc -j ACCEPT             # from $container_ip outward.

  # A list of port forwards. These are "forward all" for external traffic, container-originated traffic
  # and locally generated traffic.

  up iptables -t nat -A PREROUTING -i $base1 -d $secondary_ip -m conntrack --ctstate NEW -j DNAT --to-destination $container_ip
  up iptables -t nat -A PREROUTING -i $lxc -d $secondary_ip -m conntrack --ctstate NEW -j DNAT --to-destination $container_ip
  up iptables -t nat -A OUTPUT -d $secondary_ip -m conntrack --ctstate NEW -j DNAT --to-destination $container_ip
  
  # We flag container traffic so as to avoid natting it later on:

  up iptables -t mangle -A INPUT -s $lxc_sub -m conntrack --ctstate NEW -j CONNMARK --or-mark $connmark
  up iptables -t mangle -A OUTPUT -d $lxc_sub -m conntrack --ctstate NEW -j CONNMARK --or-mark $connmark

  # Traffic originating from the LXC subnet and targetted at the LXC subnet will always (normally)
  # be traffic that originates from a container directed at its own (or another container's) port forward.
  
  # This traffic will have been destination-NATted by the above port-forwarding rule number #2.

  # To ensure it looks like external traffic, so the container is not suddenly connected directly
  # to itself without it expecting such a thing, I also change the source address to the external IP.

  up iptables -t nat -A POSTROUTING -s $lxc_sub -o $lxc -m connmark ! --mark $connmark/$connmark -j SNAT --to-source $secondary_ip

  # The benefit is that the container can use its own port-forwarded ports on the external address without
  # any problem whatsoever.

  # And now a pretty standard MASQUERADE-ing rule.

  up iptables -t nat -A POSTROUTING -s $lxc_sub -o $base1 -j MASQUERADE

  # I do not know if the following is still required. But I think it is:

  up ip link set promisc on dev $lxc     # <-- may be required for container-to-container forwards.

  # Upon link down I am not going to remove those firewall rules.

  down ip rule del from all to 192.168.0.0/16 lookup main
  down ip rule del from all to 10.0.0.0/8 lookup main
  down ip rule del from $lxc_sub lookup second

EOF

[ $verbose ] && echo "====================================================" || echo
