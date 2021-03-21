#!/bin/bash -e

[ $# -eq 1 ] || {
    echo "Pass a video file to check if it's interlaced." >&2
    echo "Prints 'interlaced' if interlaced." >&2
    echo "Prints 'progressive' if progressive." >&2
    exit 1
}

function debug {
    [ "$DEBUG" = "interlaced" ] && echo -e "$1" 1>&2
    return 0
}

BASENAME=$(basename "$1")
STATEFILE="BSG/state/interlaced/$BASENAME"
debug "Check state file: $STATEFILE"
[ -f "$STATEFILE" ] && cat "$STATEFILE" && exit 0

DATA=$(ffmpeg -i "$1" -an -frames:v 1000 -filter:v idet -f rawvideo -y /dev/null 2>&1 | grep -i 'parsed_idet') || {
    echo "ffmpeg failed to parse file: '$1'" >&2
    exit 1
}
debug "$DATA"

RE1="Single frame detection: TFF: *([[:digit:]]+) *BFF: *([[:digit:]]+) *Progressive: *([[:digit:]]+) *Undetermined: *([[:digit:]]+)"
RE2="Multi frame detection: TFF: *([[:digit:]]+) *BFF: *([[:digit:]]+) *Progressive: *([[:digit:]]+) *Undetermined: *([[:digit:]]+)"

[[ $DATA =~ $RE1 ]] && {
    TFF1="${BASH_REMATCH[1]}" && BFF1="${BASH_REMATCH[2]}" && PROG1="${BASH_REMATCH[3]}" && UNDET1="${BASH_REMATCH[4]}"
} || {
    echo "No match on single frame detection" >&2
    exit 1
}
debug "tff: $TFF1 bff: $BFF1 progressive: $PROG1 undetermined: $UNDET1"

[[ $DATA =~ $RE2 ]] && {
    TFF2="${BASH_REMATCH[1]}" && BFF2="${BASH_REMATCH[2]}" && PROG2="${BASH_REMATCH[3]}" && UNDET2="${BASH_REMATCH[4]}"
} || {
    echo "No match on multi frame detection" >&2
    exit 1
}
debug "tff: $TFF2 bff: $BFF2 prog: $PROG2 undetermined: $UNDET2"

VALUES="Single frame: tff=$TFF1 bff=$BFF1 progressive=$PROG1 undetermined=$UNDET1\nDouble frame: tff=$TFF2 bff=$BFF2 prog=$PROG2 undetermined=$UNDET2"

# If progressive is in the hundreds and T/BFF's are in the single
# digits, it's progressive, regardless of the undetermined frames.
[ $TFF1 -lt 10 ] && [ $BFF1 -lt 10 ] && [ $PROG1 > 150 ] && ANSWER1=progressive
[ $TFF2 -lt 10 ] && [ $BFF2 -lt 10 ] && [ $PROG2 > 150 ] && ANSWER2=progressive
[ "$ANSWER1" = progressive ] && [ "$ANSWER2" = progressive ] && {
    debug "Progressive based on low TFF/BFF and high PROG numbers"
    echo progressive
    exit 0
}

# If undetermined is the highest number, abort
[ $UNDET1 -gt $TFF1 ] && [ $UNDET1 -gt $BFF1 ] && [ $UNDET1 -gt $PROG1 ] && {
    echo "Single frame detection was undetermined" >&2
    echo -e "$VALUES" >&2
    exit 1
}
[ $UNDET2 -gt $TFF2 ] && [ $UNDET2 -gt $BFF2 ] && [ $UNDET2 -gt $PROG2 ] && {
    echo "Multi frame detection was undetermined" >&2
    echo -e "$VALUES" >&2
    exit 1
}

# If top- or bottom-frame-first numbers are bigger, it's interlaced. If not, progressive.
[ $TFF1 -gt $PROG1 ] || [ $BFF1 -gt $PROG1 ] && ANSWER1=interlaced || ANSWER1=progressive
[ $TFF2 -gt $PROG2 ] || [ $BFF2 -gt $PROG2 ] && ANSWER2=interlaced || ANSWER2=progressive

# If single and multi disagree, abort
[ $ANSWER1 = $ANSWER2 ] || {
    echo "Got different answers from single and multi" >&2
    echo -e "$VALUES" >&2
    exit 1
}
echo $ANSWER1
