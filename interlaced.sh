#!/bin/bash -e

MYDIR="$(dirname "$0")"

function debug {
    [[ "$DEBUG" =~ "interlaced" ]] && echo -e "$1" 1>&2
    return 0
}

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
	-k|--cache-key)
	    cache_key="$2"
	    shift 2
	    ;;
	*)
	    echo "Unknown arg: $1"
	    exit 1
	    ;;
    esac
done

[ -f "$input" ] || {
    cat << EOF >&2
Set input file with -i or --input.

Input can be a video file to sample or the output of running a
video through ffmpeg's idet filter. Indicate which with the
-f/--format option.

Pass a cache key with -k|--cache-key. This will be used as a path
to create cache files in the cache dir, instead of the default
path munging.

Outputs "interlaced" or "progressive" to indicate the interlacing
state of the input.

EOF
    exit 1
}

input_without_slashes="${input//\//_}"
input_without_leading_dot="${input_without_slashes/#./_}"
CACHEKEY=${cache_key:-$input_without_leading_dot}
CACHEFILE="cache/interlaced/$CACHEKEY"
USECACHE=${USECACHE:-true}
[ "$USECACHE" = true ] && {
    debug "Check cache file: $CACHEFILE"
    [ -f "$CACHEFILE" ] && cat "$CACHEFILE" && exit 0
}

[ "$format" = "video" ] || [ "$format" = "output" ] || {
    cat << EOF >&2
Set format with -f or --format.

Format must be one of "video" or "output":

- video: The input arg is the path to a video file. The video stream
  will be sampled and analyzed.

- output: The input arg is a file with output from running the ffmpeg
  "idet" filter. I.e. a video stream has already been run through the
  filter. Just scan the output in the file and determine the
  interlacing status

EOF
    exit 1
}

if [ "$format" = "video" ]; then
    debug "Sampling video file"
    debug " - $(date)"
    DATA=$("$MYDIR/sample.sh" "$input" 10 | ffmpeg -hwaccel cuda -hwaccel_output_format cuda -i pipe: -filter:v idet -f rawvideo -y /dev/null 2>&1 | grep -i 'parsed_idet') || {
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

VALUES="Single frame: tff=$TFF1 bff=$BFF1 progressive=$PROG1 undetermined=$UNDET1\nDouble frame: tff=$TFF2 bff=$BFF2 progressive=$PROG2 undetermined=$UNDET2"

# If progressive frames greatly outweight interlaced, it's progressive
[ $PROG1 -gt $((100*(TFF1+BFF1))) ] && {
    debug "Decided single=progressive because progressive frames greatly outweigh interlaced."
    ANSWER1=progressive
}
[ $PROG2 -gt $((100*(TFF2+BFF2))) ] && {
    debug "Decided multi=progressive because progressive frames greatly outweigh interlaced."
    ANSWER2=progressive
}
# Similarly in the other direction
[ $((TFF1+BFF1)) -gt $((100*PROG1)) ] && {
    debug "Decided single=interlaced because interlaced frames greatly outweigh progressive."
    ANSWER1=interlaced
}
[ $((TFF2+BFF2)) -gt $((100*PROG2)) ] && {
    debug "Decided multi=interlaced because interlaced frames greatly outweigh progressive."
    ANSWER2=interlaced
}

# If nothing has worked yet and undetermined is the highest number, abort
[ -z "$ANSWER1" ] && [ $UNDET1 -gt $TFF1 ] && [ $UNDET1 -gt $BFF1 ] && [ $UNDET1 -gt $PROG1 ] && {
    echo "Single frame detection was undetermined" >&2
    echo -e "$VALUES" >&2
    exit 1
}
[ -z "$ANSWER2" ] && [ $UNDET2 -gt $TFF2 ] && [ $UNDET2 -gt $BFF2 ] && [ $UNDET2 -gt $PROG2 ] && {
    echo "Multi frame detection was undetermined" >&2
    echo -e "$VALUES" >&2
    exit 1
}

debug "Undetermined frames don't keep us from continuing."

# If we don't have an answer yet but made it past the "undetermined" check, then whichever frame count is biggest wins.
[ -z "$ANSWER1" ] && {
    if [ $TFF1 -gt $PROG1 ] || [ $BFF1 -gt $PROG1 ]; then
	debug "Decided single=interlaced because there are more interlaced frames than progressive."
	ANSWER1=interlaced
    else
	debug "Decided single=progressive because there are more progressive frames than interlaced."
	ANSWER1=progressive
    fi
}

[ -z "$ANSWER2" ] && {
    if [ $TFF2 -gt $PROG2 ] || [ $BFF2 -gt $PROG2 ]; then
	debug "Decided multi=interlaced because there are more interlaced frames than progressive."
	ANSWER2=interlaced
    else
	debug "Decided multi=progressive because there are more progressive frames than interlaced."
	ANSWER2=progressive
    fi
}

# If single and multi disagree, abort
[ $ANSWER1 = $ANSWER2 ] || {
    echo "Got different answers from single and multi" >&2
    echo -e "$VALUES" >&2
    exit 1
}
mkdir -p "$(dirname "$CACHEFILE")"
echo "$ANSWER1" > "$CACHEFILE" || true
echo $ANSWER1
