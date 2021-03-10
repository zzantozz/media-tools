#!/bin/bash

[ $# -eq 1 ] || {
	echo "Pass a video file to check if it's interlaced."
	echo "Prints 'interlaced' if interlaced."
	echo "Prints 'progressive' if progressive."
	exit 1
}

BASENAME=$(basename "$1")
STATEFILE="BSG/state/interlaced/$BASENAME"
[ "$DEBUG" = true ] && echo "Check state file: $STATEFILE"
[ -f "$STATEFILE" ] && cat "$STATEFILE" && exit 0

DATA=$(ffmpeg -i "$1" -an -frames:v 1000 -filter:v idet -f rawvideo -y /dev/null 2>&1 | grep -i 'parsed_idet')
[ "$DEBUG" = true ] && echo "$DATA"

RE1="Single frame detection: TFF: *([[:digit:]]+) *BFF: *([[:digit:]]+) *Progressive: *([[:digit:]]+) *Undetermined: *([[:digit:]]+)"
RE2="Multi frame detection: TFF: *([[:digit:]]+) *BFF: *([[:digit:]]+) *Progressive: *([[:digit:]]+) *Undetermined: *([[:digit:]]+)"

[[ $DATA =~ $RE1 ]] && {
	TFF1="${BASH_REMATCH[1]}" && BFF1="${BASH_REMATCH[2]}" && PROG1="${BASH_REMATCH[3]}" && UNDET1="${BASH_REMATCH[4]}"
} || {
	echo "No match on single frame detection" >&2
	exit 1
}
[ "$DEBUG" = true ] && echo $TFF1 $BFF1 $PROG1 $UNDET1

[[ $DATA =~ $RE2 ]] && {
	TFF2="${BASH_REMATCH[1]}" && BFF2="${BASH_REMATCH[2]}" && PROG2="${BASH_REMATCH[3]}" && UNDET2="${BASH_REMATCH[4]}"
} || {
	echo "No match on multi frame detection" >&2
	exit 1
}
[ "$DEBUG" = true ] && echo $TFF2 $BFF2 $PROG2 $UNDET2

[ $UNDET1 -gt $TFF1 -a $UNDET1 -gt $BFF1 -a $UNDET1 -gt $PROG1 ] && {
	echo "Single frame detection was undetermined" >&2
	exit 1
}
[ $UNDET2 -gt $TFF2 -a $UNDET2 -gt $BFF2 -a $UNDET2 -gt $PROG2 ] && {
	echo "Multi frame detection was undetermined" >&2
	exit 1
}

[ $TFF1 -gt $PROG1 -o $BFF1 -gt $PROG1 ] && ANSWER1=interlaced || ANSWER1=progressive
[ $TFF2 -gt $PROG2 -o $BFF2 -gt $PROG2 ] && ANSWER2=interlaced || ANSWER2=progressive
[ $ANSWER1 = $ANSWER2 ] || {
	echo "Got different answers from single and multi" >&2
	exit 1
}
echo $ANSWER1

