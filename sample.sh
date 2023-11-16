#!/bin/bash -e

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
        -o|--output)
            output="$2"
            shift 2
            ;;
        -m|--min-length)
            MINLENGTH="$2"
            shift 2
            ;;
        *)
            echo "Unknown arg: $1"
            exit 1
            ;;
    esac
done

die() {
  echo "ERROR: $1" >&2
  exit 1
}

[ -f "$input" ] || die "You must specify an input file with -i"
[ "$format" = "pipe" ] || [ "$format" = "file" ] || die "Format (-f) must be one of 'pipe' or 'file'"
[ "$format" = "file" ] && [ -z "$output" ] && die "With format 'file', you must supply an output file with -o"
[ -z "$MINLENGTH" ] && MINLENGTH=30

function debug {
    [[ "$DEBUG" =~ sample ]] && echo "$1" >&2
    return 0
}
MYDIR="$(cd "$(dirname "$0")" && pwd)"

IFS=':.' read -r h m s fraction <<<"$(ffprobe -v error -select_streams v:0 -show_entries stream_tags=DURATION-eng -of default=noprint_wrappers=1:nokey=1 "$input")"
h="10#$h"
m="10#$m"
s="10#$s"
debug "h: $h m: $m s: $s rest: $fraction"
TOTALSECS=$((h*3600 + m*60 + s))
# If shorter than the minimum just do the whole thing.
if [ $TOTALSECS -lt $((MINLENGTH*60)) ]; then
    debug "Input is less than min length of $MINLENGTH minutes, so not sampling"
    CMD=(ffmpeg -i "$input" -map 0:0 -c copy)
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
        INPUTS+=(-ss "$TS" -i "$input")
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
    CMD+=(-map [final] -t "$TOTALLEN" -f matroska)
fi
if [ "$format" = pipe ]; then
  CMD+=(pipe:)
else
  CMD+=("$output")
fi
if [[ "$DEBUG" =~ sample ]]; then
  for arg in "${CMD[@]}"; do
    echo -n "\"${arg//\"/\\\"}\" " >&2
  done
  echo
fi
if [[ "DEBUG" =~ sample ]]; then
    "${CMD[@]}"
else
    "${CMD[@]}" 2>/dev/null
fi
