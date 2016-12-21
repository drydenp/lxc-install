#!/bin/sh

# This script merely copies two files for installation on my system.
#

mkdir -p /root/fw && {
	f1=/root/fw/firewall_hooks.sh
	cp firewall_hooks.sh $f1 &&
	chmod +x $f1 &&
	echo "Created $f1"
}
