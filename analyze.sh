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
USECACHE=${USECACHE:-true}
if [ -f "$CACHEFILE" ] && [ "$USECACHE" = true ]; then
    debug "Found cached data in '$CACHEFILE'"
    cat "$CACHEFILE"
    exit 0
fi
debug "No cached data found, analyzing input file"
TMP="$(mktemp)"
debug " - $(date)"
$MYDIR/sample.sh "$1" 30 | ffmpeg -y -i pipe: -filter 'idet,cropdetect=round=2' -f null /dev/null &> "$TMP"
debug " - $(date)"

[ $USECACHE = true ] && mkdir -p "$(dirname "$CACHEFILE")"
if INTERLACED=$("$MYDIR/interlaced.sh" -i "$TMP" -f output); then
    debug "Interlaced: $INTERLACED"
    echo "INTERLACED=$INTERLACED"
    [ $USECACHE = true ] && echo "INTERLACED=$INTERLACED" >> "$CACHEFILE"
else
    debug "Interlace detection failed, but continuing, since it could be set manually"
fi
if CROPPING=$("$MYDIR/crop.sh" -i "$TMP" -f output); then
    debug "Cropping: $CROPPING"
    echo "CROPPING=$CROPPING"
    [ $USECACHE = true ] && echo "CROPPING=$CROPPING" >> "$CACHEFILE"
else
    debug "Crop detect failed, but continuing, since it could be set manually"
fi
rm "$TMP"
