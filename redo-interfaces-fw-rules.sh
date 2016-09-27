#!/bin/sh

# This file simply takes all of the "up iptables -t <table> -A <rule>" from the entire
# /etc/network/interfaces file and executes them if an identical version is not present
# in the current iptables ruleset. The reason for this is that your firewall package
# may replace whatever changes you have made prior to its loading.

# My firewall package does not provide hooks; of course I could create a standalone
# script to run after it runs. However in this way I can just feed them to /etc/network/interfaces
# and be independent of the firewall package in a way too. Instead of requiring another
# file I can just dump my commands in the appropriate places and the most important ones I
# can rerun.

# This implies that I will:
# - redo the mangle table
# - redo the nat table.

cat /etc/network/interfaces | grep "up iptables -t" | sed "s/up//" | while read line; do
  check=$(echo "$line" | sed "s/-[AI]/-C/")
  delete=$(echo "$line" | sed "s/-[AI]/-D/")
  contents=$(echo "$line" | sed "s/\s*iptables\s*//")

  echo "$check" | sh 2> /dev/null && { echo "Not adding $contents"; } || {
    echo "Adding $contents"
    echo "$line" | sh
  }
done
