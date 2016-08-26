#!/bin/sh

echo "
This will copy a few files to /root/fw and ask you to input a few values for the regeneration script for your local system. You may create a template file called TEMPLATE as follows

lxc_sub 10.3.0.0
secondary_ip x.x.x.x

to automate this step.
"

out=$(script/copy.sh) &&
script/template.sh
echo "$out
"
