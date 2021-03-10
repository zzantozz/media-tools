#!/bin/bash -e

[ "$#" -eq 2 ] || {
  echo "Supply two args: an input file and the 0-based subtitle stream to add 'forced' to."
  exit 1
}
INFILE="$1"
STREAMIDX=$2
[ -z "$OUTDIR" ] && OUTDIR=/mnt/x/ripping/__transformations

BASENAME=$(basename "${INFILE%.*}")
EXT="${INFILE##*.}"
OUTFILE="$OUTDIR/$BASENAME-with-sub-$STREAMIDX-forced.$EXT"

echo "Setting subtitle $STREAMIDX to forced in $INFILE"
echo "Output: $OUTFILE"

ffmpeg -y -i "$INFILE" -map 0 -c copy -disposition:s:$STREAMIDX forced "$OUTFILE"

echo -e "\n\n\nDone!\n"
read -p "Replace original file with output? (yes/no) " REPLY
[ "${REPLY,,}" = "yes" ] && {
  mv "$OUTFILE" "$INFILE"
  echo "Replaced."
}
