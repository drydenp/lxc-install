#!/bin/sh

# This script merely copies two files for installation on my system.
#

mkdir -p /root/fw && {
	f1=/root/fw/interfaces-renew.sh
	cp redo-interfaces-fw-rules.sh $f1 &&
	chmod +x $f1 &&
	echo "Created $f1"

	f2=/root/fw/vuurmuur_replace.sh &&
	cp vuurmuur-replace.sh $f2 &&
	chmod +x $f2
	echo "Created $f2"
	echo
}
