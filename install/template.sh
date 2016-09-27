#!/bin/bash

# This script merely turns the regenerate "template" file (template-....sh) into a
# functioning script by replacing some values.

# It does this by taking values from the VALUES file.

outfile=/root/fw/regen-script-for-smn-dpc-network.sh

values_file=$(dirname $0)/VALUES

get() {
	set -o pipefail
	eval $1=$(cat $values_file | grep $1 | sed "s/$1\s*//")
}

[ -r "$values_file" ] && {
	get lxc_sub && get secondary_ip
} || {
	read -ep "Enter subnet for lxc bridge device: [10.3.0.0] " lxc_sub
	lxc_sub=${lxc_sub:-10.3.0.0}
	read -ep "Enter IP for secondary device: [no default] " secondary_ip
}

cat template-regeneration-script.sh | sed "s/{LXC_SUB}/$lxc_sub/;s/{SECONDARY_IP}/$secondary_ip/" > "$outfile" && {
	chmod +x $outfile
	echo
	echo "Created $outfile"
}
