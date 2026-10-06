#!/bin/bash
# Extract a G-NET PC card CHD to the pieces the core needs (R25):
#   <set>.img    raw card data (40,960,000 bytes, 80,000 x 512-byte sectors)
#   <set>.idnt   512-byte ATA IDENTIFY response (CHD metadata IDNT)
#   <set>.key    5-byte Taito Type 1 unlock key (CHD metadata KEY)
#   <set>.cis    card information structure (CHD metadata CIS)
#   <set>.gddd   geometry string (CHD metadata GDDD)
# Output goes to sim/cards/ (gitignored: game data is copyrighted).
#   tools/extract_card.sh <set> [<chd name>]
set -euo pipefail
cd "$(dirname "$0")/.."
set=$1; chd=roms/$set/${2:-$set}.chd; out=sim/cards
mkdir -p $out
chdman extractraw -f -i "$chd" -o $out/$set.img > /dev/null
for tag in IDNT KEY CIS GDDD; do
  t=$(echo $tag | tr 'A-Z' 'a-z')
  chdman dumpmeta -f -i "$chd" -t "$( [ $tag = KEY ] && echo 'KEY ' || [ $tag = CIS ] && echo 'CIS ' || echo $tag )" -o $out/$set.$t > /dev/null
done
printf '%s img %s bytes md5 %s key %s\n' $set $(stat -f %z $out/$set.img) $(md5 -q $out/$set.img) $(xxd -p $out/$set.key)
