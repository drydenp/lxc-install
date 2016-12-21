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

# First virtual device, as a test

alias0="${eth0}:0"
base0="${alias0%:*}"

# Iptables cannot work with aliased devices. We must use regular existing interfaces
# in our iptables rules. I will still for now differentiate between base0 and base1.
# They will normally point to the same device (interface).

primary_ip=$(ip addr show dev $base0 | grep "inet " | grep "$alias0$" | head -1 | awk '{print $2'} | sed "s@/..@@")
primary_gateway=${primary_ip%.*}.1

# The virtual device we will use to hold our secondary IP:

alias1="${eth0}:1"
base1="${alias1%:*}"

# Base1 is going to be the prime "recepticle" for our custom firewall.

secondary_ip={SECONDARY_IP}
secondary_gateway=${secondary_ip%.*}.1

# Next up is the internal network for the internal hosts:

lxc=lxc-nat-bridge
lxc_sub={LXC_SUB}/24

# Our host system (main system) will have first IP on the subnet just defined:

internal_ip=${lxc_sub%.0/*}.1

# The (first) container will get second IP:

container_ip=${lxc_sub%.0/*}.2


# The above values SECONDARY_IP and LXC_SUB are substituted from a template VALUES file.

# ConnMark value: this is bit number 5 (6th bit) - I use this bit to be safe with firewalls that may use earlier bits.
connmark=32

# ---------------------------------------------------------------------------- #
# Some simple routines for removing and adding config values from files.

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

# The following sets up hosts.allow and hosts.deny in reverse order.

$config_do /etc/hosts.deny "ALL: ALL EXCEPT 127. [::1]/128 10. 192.168."
    # deny all except localhost and 10.* and 192.168.*

$config_do /etc/hosts.allow "ALL@${primary_ip}: ALL"
    # allow requests targetting the primary IP

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
  up echo 1 > /proc/sys/net/ipv6/conf/$eth0/disable_ipv6

iface $alias0 inet dhcp

iface $alias1 inet static
  address $secondary_ip
  netmask 255.255.255.0

  # We'll need to wait until the prime interfaces is loaded:

  pre-up count=0; while ! ip addr show dev $base0 | grep "inet " | grep "$alias0$" && [ \$count -lt 5 ]; do sleep 1s; count=\$(( count+1 )); done

  # Outgoing traffic originating from the container(s) and our \$secondary_ip ($secondary_ip)
  # is for my system going to use a secondary gateway as well.
  # To route traffic over this gateway we need an ip rule and a secondary routing table.

  # There are two ways of approaching that.
  # 1. Copy all entries from main table to second table and replace default route for different gateway.
  # 2. Only place default route in new table and create exceptions for locally destined traffic in ip rules.

  # #1 has the following form:
  # -- rule: traffic originating from 10.3.0.0 is surely destined for the second gateway.
  # -- rule: traffic originating from $secondary_ip is surely destined for the second gateway.

  # #2 has the following form:
  # -- same rules as above.
  # -- rule: traffic destined for 10.3.0.0 must use main table
  # -- rule: traffic destined for (local area network) must use main table.
  # -- rule: traffic destined for (vpn) must use main table.
  # -- and so on.

  # Benefit of #1:
  # -- routing table is duplicated and newly available networks need to trigger another duplication.
  # -- copy code is always the same
  # -- only relevant if you want locally generated traffic to reach local networks (e.g. vpn)

  # Benefit of #2:
  # -- simple routing table of 1 entry
  # -- same amount of work: need an exception for every destination address added to the ruleset.

  # Downside of #2:
  # -- annoying reordering of rules ("to" rules need to be below "from" rules and the order is not clear.
  # -- depending on perfect ruleset for proper routing

  # Downside of #1:
  # -- after every new interface the 2nd table must be updated such as with VPN and this can be messy
  #    particularly if you won't do it ;-). If you don't do it, you can't reach the VPN from the
  #    containers but this applies to #2 as well.

  # I consider the duplicate table to be more resilient and hence more trustworthy. It's the same
  # operation each time but may leave routing tables behind. May leave stale entries behind in the
  # 2nd table if you do a lot of connecting.


  # Copy over the routing table to table "second" (2).

  up ip route show | grep -v ^default | while read line; do ip route add \$line table second; done
  up ip route add default via $secondary_gateway dev $base1 table second
  up ip rule add from $secondary_ip lookup second

  down ip rule del from $secondary_ip lookup second
  down ip route flush table second

iface $lxc inet static
  bridge_ports none
  bridge_fd 0
  address $internal_ip
  netmask 255.255.255.0

  # Wait here too:

  pre-up count=0; while ! ip addr show dev $base1 | grep "inet " | grep "$alias1$" && [ \$count -lt 5 ]; do sleep 1s; count=\$(( count+1 )); done

  # Make life a little easier:

  up echo 1 > /proc/sys/net/ipv6/conf/$lxc/disable_ipv6
 
  # Since this interface creates a new route we once more copy it over to the
  # second table.

  up ip route show | grep "^$lxc_sub" | { read line; ip route add \$line table second; }
  up ip rule add from $lxc_sub lookup second

  # These rules will be overwritten by any firewall package firing after this:

  up iptables -A FORWARD -i $base1 -o $lxc -j ACCEPT   # forwards to containers always accepted
  up iptables -A FORWARD -i $base1 -j DROP             # other forwards denied (such as to a lan)
  up iptables -I FORWARD -i $lxc -j ACCEPT             # the firewall may handle this more delicately

  # These are port forwards for external traffic, container-originated traffic, and locally
  # generated traffic:

  up iptables -t nat -A PREROUTING -i $base1 -d $secondary_ip -m conntrack --ctstate NEW -j DNAT --to-destination $container_ip
  up iptables -t nat -A PREROUTING -i $lxc -d $secondary_ip -m conntrack --ctstate NEW -j DNAT --to-destination $container_ip
  up iptables -t nat -A OUTPUT -d $secondary_ip -m conntrack --ctstate NEW -j DNAT --to-destination $container_ip
  
  # This flags internally generated traffic destined for or originating from the containers.
  # The result is that we can skip doing anything to it later on.

  up iptables -t mangle -A OUTPUT -d $container_ip -m conntrack --ctstate NEW -j CONNMARK --or-mark $connmark
  up iptables -t mangle -A INPUT -s $container_ip -m conntrack --ctstate NEW -j CONNMARK --or-mark $connmark

  # The \$connmark variable is set to $connmark (32) such that we have a bit (0b100000) that we can use
  # for our own purposes.

  # My personal firewall package also uses connmark bits and not very conveniently (as actual values),
  # such that I perform the following mutation after it has loaded to make its values (0, 1, 2) suitable
  # for coexisting with other values:

  # iptables-save | sed "s@ 0x\([012]\) @ 0x\1/0x3 @;s@0x\([12]\)/0xffffffff@0x\1/0x3@" | iptables-restore

  # That just masks the values properly so I can use my bit number 6.

  # Packets originating from the LXC subnet and outgoing TO a container must (currently) have been
  # targetted at my public secondary IP! How awful, but I want them to appear as coming from that IP:

  up iptables -t nat -A POSTROUTING -s $lxc_sub -o $lxc -m connmark ! --mark $connmark/$connmark -j SNAT --to-source $secondary_ip

  # That makes it appear as an external request (loopback of sorts) to the internal servers of the container.
  # That means the container can use its own services through the external IP without issue and appear to
  # originate from the external IP. Otherwise they will simply get DNATted to itself and I'm not sure (any
  # longer) what problems that causes. Other than that the service gets a response from a different IP than
  # what it was talking to originally. Sometimes that is handled without issue but I had problems before.

  # If you have more containers that need to talk to each other, this will create problems. But I could just
  # mangle such packets in the PREROUTING chain if they end up being forwarded at all. Note sure they will
  # (in and out of the same interface = no forward). The whole reason for this is that I want to be able
  # to cover all containers but the subnet contains "me" as well. I can match all containers individually
  # but I just flag myself using the \$connmark in order to exclude myself from the above rule. Pretty
  # complicated but I think there were issues with using the external address without further ado.

  up iptables -t nat -A POSTROUTING -s $lxc_sub -o $base1 -j MASQUERADE

  # The above is a typical standard masquerading rule.

  up ip link set promisc on dev $lxc

  # The above is or was required for the container to access its own port forwards.

  # Last but not least the complete lack of reverses of everything I have done:

  down ip rule del from $lxc_sub lookup second

EOF

[ $verbose ] && echo "====================================================" || echo
