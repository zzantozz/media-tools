#!/bin/bash -e

MYDIR="$(dirname "$0")"

function debug {
    [ "$DEBUG" = "interlaced" ] && echo -e "$1" 1>&2
    return 0
}

positional=()
while [ $# -gt 0 ]; do
    key="$1"
    case "$key" in
	-i|--input)
	    input="$2"
	    shift 2
	    ;;
	-f|--format)
	    format="$2"
	    shift 2
	    ;;
	*)
	    positional+=("$1")
	    shift
	    ;;
    esac
done

[ -f "$input" ] || {
    cat << EOF >&2
Set input file with -i or --input.

Input can be a video file to sample or the output of running a
video through ffmpeg's idet filter. Indicate which with the
-f/--format option.

Outputs "interlaced" or "progressive" to indicate the interlacing
state of the input.

EOF
    exit 1
}

BASENAME=$(basename "$input")
CACHEFILE="cache/interlaced/$BASENAME"
debug "Check cache file: $CACHEFILE"
[ -f "$CACHEFILE" ] && cat "$CACHEFILE" && exit 0

[ "$format" = "video" ] || [ "$format" = "output" ] || {
    cat << EOF >&2
Set format with -f or --format.

Format must be one of "video" or "output":

- video: The input arg is the path to a video file. The video stream
  will be sampled and analyzed.

- output: The input arg is a file with output from running the ffmpeg
  "idet" filter. I.e. a video stream has already been run throug the
  filter. Just scan the output in the file and determine the
  interlacing status

EOF
    exit 1
}

if [ "$format" = "video" ]; then
    debug "Sampling video file"
    debug " - $(date)"
    DATA=$("$MYDIR/sample.sh" "$input" 10 | ffmpeg -i pipe: -filter:v idet -f rawvideo -y /dev/null 2>&1 | grep -i 'parsed_idet') || {
	echo "ffmpeg failed to parse file: '$input'" >&2
	exit 1
    }
    debug " - $(date)"
    debug "Sampled data:"
    debug "$DATA"
elif [ "$format" = "output" ]; then
    DATA="$(grep -i 'parsed_idet' "$input")"
    debug "Data from output file:"
    debug "$DATA"
fi

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
