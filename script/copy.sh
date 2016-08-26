#!/bin/sh

mkdir -p /root/fw && {
	f1=/root/fw/interfaces-renew.sh 
	cp renew-interfaces-firewall-rules.sh $f1 &&
	chmod +x $f1 &&
	echo "Created $f1"

	f2=/root/fw/vuurmuur_replace.sh &&
	cp vuurmuur-replace-marks.sh $f2 &&
	chmod +x $f2
	echo "Created $f2"
	echo
}
