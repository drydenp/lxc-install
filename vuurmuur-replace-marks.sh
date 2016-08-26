#!/bin/sh

# This script merely replaces the "unqualified" usages of the conntrack marks (connmark)
# by the Vuurmuur package with "qualified" ones.

# What I mean is that Vuurmuur uses connmark 0 to 2 as individual, distinct values (no bits).
# So they are not flags but values 0, 1 and 2.

# As such they have a limited reach and should only be used for that reach.

# Vuurmuur by default as of this writing (April 2016) uses them in an unqualified way that prohibts using those values for other stuff (by using bitmasks, or "orring" values into them).

# This small script changes:
#  0x0 to 0x0/0x3
#  0x1 to 0x1/0x3
#  0x2 to 0x2/0x3

#  0x1/0xffffffff to 0x1/0x3
#  0x2/0xffffffff to 0x2/0x3

# In this way any higher bits remain accessible to us, because it does not modify them, nor does it read them.

iptables-save | sed "s@ 0x\([0-2]\) @ 0x\1/0x3 @;s@0x\([1-2]\)/0xffffffff@0x\1/0x3@" | iptables-restore
