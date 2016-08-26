#!/bin/sh

cat /etc/network/interfaces | grep "up iptables -t" | sed "s/up//" | while read line; do
  check=$(echo "$line" | sed "s/-[AI]/-C/")
  delete=$(echo "$line" | sed "s/-[AI]/-D/")
  contents=$(echo "$line" | sed "s/\s*iptables\s*//")

  echo "$check" | sh 2> /dev/null && { echo "Not adding $contents"; } || {
    echo "Adding $contents"
    echo "$line" | sh
  }
done
