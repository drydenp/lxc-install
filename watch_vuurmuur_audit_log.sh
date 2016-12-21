#!/bin/sh

# This goes into daemon mode and just keeps running.

# Call it a terrible system service and I will create a systemd service file for it too.

while true; do sleep 5s; logtail -f/var/log/vuurmuur/audit.log -o/var/log/vuurmuur/.audit.log.logtail-file | grep "Applying changes" > /dev/null && /root/fw/firewall_hooks.sh; done
