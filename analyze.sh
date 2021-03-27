#!/bin/bash -e

[ -n "$1" ] || {
    echo "Pass one arg, the name of a video file, to scan it for" >&2
    echo "important attributes needed for transcoding." >&2
    exit 1
}

function debug {
    [ "$DEBUG" = analyze ] && echo "$1" >&2
    return 0
}

MYDIR="$(dirname "$0")"
TMP="$(mktemp)"
TMPDIR="$(mktemp -d)"
debug "Sampling input..."
debug " -- $(date)"
$MYDIR/sample.sh "$1" 30 | ffmpeg -y -i pipe: -filter 'idet,cropdetect=round=2' -f null /dev/null &> "$TMP"
debug " -- $(date)"

INTERLACED=$("$MYDIR/interlaced.sh" -i "$TMP" -f output)
CROPPING=$("$MYDIR/crop.sh" -i "$TMP" -f output)
rm "$TMP"
echo "INTERLACED=$INTERLACED"
echo "CROPPING=$CROPPING"
