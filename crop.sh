#!/bin/bash -e

MYDIR="$(dirname "$0")"

function debug {
    [ "$DEBUG" = crop ] && echo "$1" >&2
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

Input can be a video file to sample or the output of running a video
through ffmpeg's cropdetect filter. Indicate which with the
-f/--format option.

Outputs a cropping value to use with ffmpeg's crop filter to trim
black edges from the video. Use the output like
"-filter:v crop=\$VALUE".

EOF
    exit 1
}

BASENAME=$(basename "$input")
CACHEFILE="cache/crop/$BASENAME"
debug "Check cache file: $CACHEFILE"
[ -f "$CACHEFILE" ] && cat "$CACHEFILE" && exit 0

[ "$format" = "video" ] || [ "$format" = "output" ] || {
    cat << EOF >&2
Set format with -f or --format.

Format must be one of "video" or "output":

- video: The input arg is the path to a video file. The video stream
  will be sampled and analyzed.

- output: The input arg is a file with output from running the ffmpeg
  "cropdetect" filter. I.e. a video stream has already been run
  through the filter. Just scan the output in the file and determine
  the crop value.

EOF
    exit 1
}

if [ "$format" = "video" ]; then
    TMP=$(mktemp)
    debug "Sampling video file"
    debug " - $(date)"
    echo "This is broken! Fix for new sample.sh input options!"
    exit 1
    "$MYDIR/sample.sh" "$input" 30 | \
	ffmpeg -i pipe: -filter "cropdetect=round=2" -f null -y /dev/null 2>&1 | \
	grep '\[Parsed_cropdetect' | sed 's/.*crop=\(.*\)/\1/' > "$TMP"
    debug " - $(date)"
    LINES="$(cat "$TMP" | wc -l)"
    debug "Sampled data had $LINES lines"
    [ "$LINES" -eq 0 ] && {
	rm "$TMP"
	echo "Something went wrong with cropdetect. No cropping lines in output." >&2
	exit 1
    }
    DATA=$(sort < "$TMP" | uniq)
    rm "$TMP"
elif [ "$format" = "output" ]; then
    DATA=$(grep '\[Parsed_cropdetect' "$input" | sed 's/.*crop=\(.*\)/\1/' | sort | uniq)
fi

MAXWIDTH=0
MAXHEIGHT=0
while read CROPLINE; do
    IFS=':' read -r w h x y <<<"$CROPLINE"
    [ $w -gt $MAXWIDTH ] && MAXWIDTH=$w
    [ $h -gt $MAXHEIGHT ] && MAXHEIGHT=$h
done <<< "$DATA"
VALUE="$(echo "$DATA" | grep "$MAXWIDTH:$MAXHEIGHT:")"
[ "$(echo "$VALUE" | wc -l)" = 1 ] || {
    echo "Multiple crop options with max width and height!" >&2
    echo "$VALUE" >&2
    exit 1
}
debug "Found best crop value based on max width and height: $VALUE"

if [[ "$VALUE" =~ :0:0$ ]]; then
    debug "Best crop is no crop"
    echo none
else
    debug "Cropping to '$VALUE'"
    echo "$VALUE"
fi
