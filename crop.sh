#!/bin/bash -e

[ -f "$1" ] || {
    echo "Enter path to a video file to determine the crop dimensions" >&2
    exit 1
}

function debug {
    [ "$DEBUG" = crop ] && echo "$1" >&2
    return 0
}

IFS=':.' read -r h m s fraction <<<"$(ffprobe -v error -select_streams v:0 -show_entries stream_tags=DURATION-eng -of default=noprint_wrappers=1:nokey=1 "$1")"
h="10#$h"
m="10#$m"
s="10#$s"
debug "h: $h m: $m s: $s rest: $fraction"
TOTALSECS=$((h*3600 + m*60 + s))
IGNORESECS=$((TOTALSECS/10))
END=$((TOTALSECS - IGNORESECS))
TS=$IGNORESECS
STREAMCOUNT=0
FILTER=""
INPUTS=()
CHARS=(a b c d e f g h i j k l m n o p q r s t u v w x y z)
STREAMNAMES=()
for c in a b c d e f g h i j k l m n o p q r s t u v w x y z; do
    for i in $(seq 1 10); do
	STREAMNAMES+=("$c$i")
    done
done
CHECKINTERVAL=$(((TOTALSECS - IGNORESECS - IGNORESECS) / 120))
[ "$CHECKINTERVAL" -lt 5 ] && CHECKINTERVAL=5
CHECKLEN=2
OUTPUTS=""
debug "Check from $IGNORESECS s to $END s of video in $CHECKINTERVAL s increments"
while [ $TS -lt $END ]; do
    OUTPUT="${STREAMNAMES[$STREAMCOUNT]}"
    INPUTS+=(-ss "$TS" -i "$1")
    FILTER="$FILTER [$STREAMCOUNT:0]trim=start=0:duration=$CHECKLEN[$OUTPUT];"
    OUTPUTS="$OUTPUTS[$OUTPUT]"
    STREAMCOUNT=$((STREAMCOUNT+1))
    TS=$((TS+CHECKINTERVAL))
    [ "$STREAMCOUNT" -gt "${#STREAMNAMES[@]}" ] && {
	echo "Too many chunks for crop checking. Fix the script."
	exit 1
    }
done
debug "Broke into $STREAMCOUNT chunks"
TOTALLEN=$((CHECKLEN*STREAMCOUNT))
CMD=(ffmpeg)
CMD+=("${INPUTS[@]}")
CMD+=(-filter_complex "$FILTER ${OUTPUTS}concat=n=$STREAMCOUNT,cropdetect=round=2")
CMD+=(-max_muxing_queue_size 1024)
CMD+=(-f null -t "$TOTALLEN" -)
# For debugging to spit the concatted stream to a file
#CMD+=(-filter_complex "$FILTER ${OUTPUTS}concat=n=$STREAMCOUNT[final]")
#CMD+=(-map [final] -c:v libx264 -preset ultrafast -t "$TOTALLEN" out.mkv)
[ "$DEBUG" = crop ] && for arg in "${CMD[@]}"; do
    echo -n "\"${arg//\"/\\\"}\" " >&2
done
[ "$DEBUG" = crop ] && echo
TMP=$(mktemp)
[ "$DEBUG" = crop ] && date
"${CMD[@]}" 2>&1 | grep '\[Parsed_cropdetect' | sed 's/.*crop=\(.*\)/\1/' > "$TMP"
[ "$DEBUG" = crop ] && date
debug "Got $(cat "$TMP" | wc -l) lines in temp file ($TMP)"
CROPDETECT=$(sort < "$TMP" | uniq)
rm "$TMP"
if [ "$(echo "$CROPDETECT" | wc -l)" = 1 ]; then
    VALUE="$CROPDETECT"
    debug "Unanimous cropdetect: $VALUE"
else
    MAXWIDTH=0
    MAXHEIGHT=0
    while read CROPLINE; do
	IFS=':' read -r w h x y <<<"$CROPLINE"
	[ $w -gt $MAXWIDTH ] && MAXWIDTH=$w
	[ $h -gt $MAXHEIGHT ] && MAXHEIGHT=$h
    done <<< "$CROPDETECT"
    VALUE="$(echo "$CROPDETECT" | grep "$MAXWIDTH:$MAXHEIGHT:")"
    [ "$(echo "$VALUE" | wc -l)" = 1 ] || {
	echo "Multiple crop options with max width and height!" >&2
	echo "$VALUE" >&2
	exit 1
    }
    debug "Found best crop value based on max width and height: $VALUE"
fi

[[ "$VALUE" =~ :0:0$ ]] && {
    debug "Best crop is no crop"
    echo none
    exit 0
}

STREAM0=$(ffprobe -i "$1" 2>&1 | grep "Stream #0:0")
debug "Stream 0: $STREAM0"
if echo "$STREAM0" | grep 1920x > /dev/null && echo "$VALUE" | grep 1920: > /dev/null; then
    debug "Crop width matches input width 1920"
    echo "$VALUE"
    exit 0
elif echo "$STREAM0" | grep 720x > /dev/null && echo "$VALUE" | grep 720: > /dev/null; then
    debug "Crop width matches input width 720"
    echo "$VALUE"
    exit 0
else
    echo "Cropdetect doesn't match input width!" >&2
    echo "Detected: $VALUE" >&2
    echo "Stream: $STREAM0"
    exit 1
fi

echo "Cropdetect wasn't unanimous. Try looking for majority or something:" >&2
echo "$CROPDETECT" >&2
debug "$CROPDETECT"
exit 1
