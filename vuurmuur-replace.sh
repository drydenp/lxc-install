#!/bin/sh

# This script does two things:

# 1. Replace uniqualified or inappropriate "vuurmuur" usage of connmarks.
# 2. Filter out "alias" firewall rules that must be of the main device (interface).

# In both cases iptables rules are manipulated.

# 1. The connmarks are changed thusly:

#  0x0 -> 0x0/0x3
#  0x1 -> 0x1/0x3
#  0x2 -> 0x2/0x3
#  0x1/0xffffffff -> 0x1/0x3
#  0x2/0xffffffff -> 0x2/0x3

# As you can see I suffix an appropriate mask, since as far as I can tell Vuurmuur only uses values 0, 1, 2.

iptables-save | sed "s@ 0x\([0-2]\) @ 0x\1/0x3 @;s@0x\([1-2]\)/0xffffffff@0x\1/0x3@" | iptables-restore

# 2. Attempt.

# ..1. Remove all lines for accounting of input and output on the secondary interface (alias).

iptables-save | sed "/\(INPUT -i\|OUTPUT -o\) eth0:1 -j ACC-eth0:1/d" |

# ..2. Remove all lines for accounting of forwards for the primary interface.

sed "/FORWARD -[io] eth0:0 -j ACC-eth0:0/d" |

# ..3. Replace all remaining occurances of the eth0:x syntax as whole words:

sed "s/ eth0:. / eth0 /g" | iptables-restore
