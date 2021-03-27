#!/bin/bash -e

[ -f "$1" ] || {
    echo "Not a file: '$1'" >&2
    echo ""
    echo "Enter path to a movie file to stream video samples to stdout." >&2
    echo "This is to do some scans or introspections of the video stream" >&2
    echo "without having to read the entire video."
    echo ""
    echo "If the video is short, it won't do samples and stream the whole" >&2
    echo "video instead." >$2
    exit 1
}
[ -z "$2" ] || [ "$2" -gt -1 ] || {
    echo "Second arg (optional) should be the number of minutes below which" >&2
    echo "sampling won't occur, and instead the whole video will be streamed." >&2
    exit 1
}
MINLENGTH="${2:-30}"

function debug {
    [ "$DEBUG" = sample ] && echo "$1" >&2
    return 0
}
MYDIR="$(dirname "$0")"

IFS=':.' read -r h m s fraction <<<"$(ffprobe -v error -select_streams v:0 -show_entries stream_tags=DURATION-eng -of default=noprint_wrappers=1:nokey=1 "$1")"
h="10#$h"
m="10#$m"
s="10#$s"
debug "h: $h m: $m s: $s rest: $fraction"
TOTALSECS=$((h*3600 + m*60 + s))
# If shorter than the minimum just do the whole thing.
if [ $TOTALSECS -lt $((MINLENGTH*60)) ]; then
    CMD=(ffmpeg -i "$1" -max_muxing_queue_size 1024 -map 0:0 -f matroska pipe:)
else
    # Ignore the two ends of the video because intros and credits tend
    # to have different characteristics.
    IGNORESECS=$((TOTALSECS/10))
    END=$((TOTALSECS - IGNORESECS))
    TS=$IGNORESECS
    STREAMCOUNT=0
    FILTER=""
    INPUTS=()
    CHECKINTERVAL=$(((TOTALSECS - IGNORESECS - IGNORESECS) / 120))
    [ "$CHECKINTERVAL" -lt 5 ] && CHECKINTERVAL=5
    CHECKLEN=2
    OUTPUTS=""
    debug "Check from $IGNORESECS s to $END s of video in $CHECKINTERVAL s increments"
    while [ $TS -lt $END ]; do
	OUTPUT="chunk$STREAMCOUNT"
	INPUTS+=(-ss "$TS" -i "$1")
	FILTER="$FILTER [$STREAMCOUNT:0]trim=start=0:duration=$CHECKLEN[$OUTPUT];"
	OUTPUTS="$OUTPUTS[$OUTPUT]"
	STREAMCOUNT=$((STREAMCOUNT+1))
	TS=$((TS+CHECKINTERVAL))
    done
    debug "Broke into $STREAMCOUNT chunks"
    TOTALLEN=$((CHECKLEN*STREAMCOUNT))
    CMD=(ffmpeg)
    CMD+=("${INPUTS[@]}")
    CMD+=(-max_muxing_queue_size 1024)
    CMD+=(-filter_complex "$FILTER ${OUTPUTS}concat=n=$STREAMCOUNT[final]")
    CMD+=(-map [final] -t "$TOTALLEN" -f matroska pipe:)
fi
[ "$DEBUG" = sample ] && for arg in "${CMD[@]}"; do
    echo -n "\"${arg//\"/\\\"}\" " >&2
done
if [ "DEBUG" = sample ]; then
    "${CMD[@]}"
else
    "${CMD[@]}" 2> /dev/null
fi

