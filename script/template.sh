#!/bin/bash

outfile=/root/fw/regen-script-for-smn-dpc-network.sh

get() {
	set -o pipefail
	eval $1=$(cat TEMPLATE | grep $1 | sed "s/$1\s*//")
}

[ -r "TEMPLATE" ] && {
	get lxc_sub && get secondary_ip
} || {
	read -ep "Enter subnet for lxc bridge device: [10.3.0.0] " lxc_sub
	lxc_sub=${lxc_sub:-10.3.0.0}
	read -ep "Enter IP for secondary device: [no default] " secondary_ip
}

cat regenerate*.sh | sed "s/{LXC_SUB}/$lxc_sub/;s/{SECONDARY_IP}/$secondary_ip/" > "$outfile" && {
	chmod +x $outfile
	echo
	echo "Created $outfile"
}
