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
CACHEDIR="cache/analyze"
MOVIEDIR="$(basename "$(dirname "$1")")"
BASENAME="$(basename "$1")"
CACHEFILE="$CACHEDIR/$MOVIEDIR/$BASENAME"
[ -f "$CACHEFILE" ] && {
    debug "Found cached data in '$CACHEFILE'"
    cat "$CACHEFILE"
    exit 0
}
debug "No cached data found, analyzing input file"
TMP="$(mktemp)"
debug " - $(date)"
$MYDIR/sample.sh "$1" 30 | ffmpeg -y -i pipe: -filter 'idet,cropdetect=round=2' -f null /dev/null &> "$TMP"
debug " - $(date)"

mkdir -p "$(dirname "$CACHEFILE")"
INTERLACED=$("$MYDIR/interlaced.sh" -i "$TMP" -f output) && {
    debug "Interlaced: $INTERLACED"
    echo "INTERLACED=$INTERLACED"
    echo "INTERLACED=$INTERLACED" >> "$CACHEFILE"
} || {
    debug "Interlace detection failed, but continuing, since it could be set manually"
}
CROPPING=$("$MYDIR/crop.sh" -i "$TMP" -f output) && {
    debug "Cropping: $CROPPING"
    echo "CROPPING=$CROPPING"
    echo "CROPPING=$CROPPING" >> "$CACHEFILE"
} || {
    debug "Crop detect failed, but continuing, since it could be set manually"
}
rm "$TMP"
