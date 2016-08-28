#!/bin/bash

[ "$1" = "remove" ] && remove=yes

# First, just read the current IP from the eth0 interface.

eth0=eth0

# Our virtual device so that the bridge can have its own IP:

virt="${eth0}:1"

# Name of the bridge we'll create

br=eth1

# Name the LXC device will have

lxc=lxc-nat-bridge

# Subnet of the LXC device:

lxc_sub={LXC_SUB}/24

# Host of the LXC device:

internal_ip=${lxc_sub%0/*}1

# Address of the container:

container_ip=${lxc_sub%0/*}2

# Obtain the main configured IP from the running system

primary_ip=$(ip addr show dev $eth0 | grep "inet " | awk '{print $2'} | sed "s@/..@@")
primary_gateway=${primary_ip%.*}.1

# PICK the secondary IP here:

secondary_ip={SECONDARY_IP}
secondary_gateway=${secondary_ip%.*}.1

# Automate changing the connmark we use a bit
cm=32

# Now first just set up the hosts.allow and hosts.deny. Set it up or revert it

config_test() {
	echo -n "Testing $1 for \"$2\"..." >&2
	cat "$1" | grep "$2" > /dev/null && {
		cat "$1" | grep "^$2" > /dev/null && {
			echo " found"
		} || { echo " found but possibly commented out."; return 2; }
	} || {
		echo " not found."
		false
	}
}

config_remove() {
	echo -n "Removing \"$2\" from $1..." >&2
	tmp=$(mktemp)
	cat "$1" | sed "\#$2#d" > $tmp
	diff "$1" "$tmp" > /dev/null && {
		echo " nothing removed." >&2
		rm $tmp
	} || {
		echo " removed." >&2
		mv $tmp "$1"
	}
}

config_install() {
	echo "Adding \"$2\" to $1" >&2
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
[ ! $remove ] && {
	config_do=config_update
} || {
	config_do=config_remove
}

$config_do /etc/hosts.deny "ALL: ALL EXCEPT 127. [::1]/128 10."
$config_do /etc/hosts.allow "ALL@${primary_ip}: ALL"
$config_do /etc/iproute2/rt_tables "$(printf "2\tsecond")"

[ $remove ] && exit

echo

echo "Recreating /etc/network/interfaces as follows. Hope it works." >&2
echo >&2
echo "====================================================" >&2
cat << EOF | tee /etc/network/interfaces >&2
# This file describes the network interfaces available on your system
# and how to activate them. For more information, see interfaces(5).

source /etc/network/interfaces.d/*

auto lo $eth0 $virt $br $lxc
allow-hotplug $virt

# The loopback network interface
iface lo inet loopback

iface $eth0 inet dhcp
  up echo 1 > /proc/sys/net/ipv6/conf/$eth0/disable_ipv6

iface $virt inet manual

iface $br inet static
  bridge_ports $virt
  bridge_fd 0
  address $secondary_ip
  netmask 255.255.255.0

  # This thing may be coming online too fast for its own good:

  pre-up sleep 5s; ip addr show dev $eth0 | grep "inet " || sleep 10s

  # An improvement, for sure?

  up echo 1 > /proc/sys/net/ipv6/conf/$br/disable_ipv6

  # there are two choices to take care of routing the outgoing traffic of the
  # container over our $secondary_ip. One is to only add the default route for it
  # and then make sure internal traffic doesn't match it by creating exception
  # rules for internal traffic; which means we might need exceptions for every
  # other subnet we have.

  # a third way I haven't been able to test properly yet is to use the "oif"
  # flag in the rule not necessitating either of these two solutions.

  # the second solution is to copy the routing table over whenever you change
  # it. We can do that for ourselves easily.

  # Copy over the routing table to table "second" (2).

  up ip route show | grep -v ^default | while read line; do ip route add \$line table second; done
  up ip route add default via $secondary_gateway dev $br table second
  up ip rule add from $secondary_ip lookup second

  down ip rule del from $secondary_ip lookup second
  down ip route flush table second

iface $lxc inet static
  bridge_ports none
  bridge_fd 0
  address $internal_ip
  netmask 255.255.255.0

  # Wait here too:

  pre-up while ! ip addr show dev $br | grep "inet "; do sleep 1s; done

  # Make life a little easier:

  up echo 1 > /proc/sys/net/ipv6/conf/$lxc/disable_ipv6
 
  # Since this interface creates a new route we once more copy it over to the
  # second table.

  up ip route show | grep "^$lxc_sub" | { read line; ip route add \$line table second; }
  up ip rule add from $lxc_sub lookup second

  # You could use these.

  up iptables -A FORWARD -i $br -o $lxc -j ACCEPT
  up iptables -A FORWARD -i $br -j DROP
  up iptables -I FORWARD -i $lxc -o $eth0 -j DROP
  up iptables -I FORWARD -i $lxc -j ACCEPT

  # Port forwards for three classes of use.

  up iptables -t nat -A PREROUTING -i $br -d $secondary_ip -m conntrack --ctstate NEW -j DNAT --to-destination $container_ip
  up iptables -t nat -A PREROUTING -i $lxc -d $secondary_ip -m conntrack --ctstate NEW -j DNAT --to-destination $container_ip
  up iptables -t nat -A OUTPUT -d $secondary_ip -m conntrack --ctstate NEW -j DNAT --to-destination $container_ip
  
  # First class: external traffic; second class: container-originating traffic.
  # Third class: internal traffic.

  # Not sure of the necessity, but this allows internal traffic to stay
  # internal:

  up iptables -t mangle -A OUTPUT -d $container_ip -m conntrack --ctstate NEW -j CONNMARK --or-mark $cm
  up iptables -t mangle -A INPUT -s $container_ip -m conntrack --ctstate NEW -j CONNMARK --or-mark $cm

  # I have chosen a connmark bit of 6 (value 32) (0b100000) because my firewall script uses
  # values from 0-2 for its states and 32 seems a safe high value no one uses.

  # I cause it to mask its values using:

  # iptables-save | sed "s@ 0x\([0-2]\) @ 0x\1/0x3 @;s@0x\([1-2]\)/0xffffffff@0x\1/0x3@" | iptables-restore

  # The result is that I can use the 3rd bit the way I want.

  # The result for now is that any packet matching the following rule will not have originated
  # from one of my interfaces:
 
  up iptables -t nat -A POSTROUTING -s $lxc_sub -o $lxc -m connmark ! --mark $cm/$cm -j SNAT --to-source $secondary_ip

  # This allows me to target the whole subnet in case we want to add more containers.
  # Otherwise it would SNAT $internal_ip to $secondary_ip which would work, but the cointainer
  # would see us as $secondary_ip instead of the internal IP.

  up iptables -t nat -A POSTROUTING -s $lxc_sub -o $br -j MASQUERADE

  # A typical masquerading rule.

  up ip link set promisc on dev $lxc

  # This is required for the container to be able to access its own port forwards.
  # And finally the complete lack of reverting scripts at present:

  down ip rule del from $lxc_sub lookup second

EOF

echo "====================================================" >&2
