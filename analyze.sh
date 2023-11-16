#!/bin/bash -e

while [ $# -gt 0 ]; do
    key="$1"
    case "$key" in
	-k|--cache-key)
	    cache_key="$2"
	    shift 2
	    ;;
	*)
	    if [ -z "$input" ]; then
		input="$1"
		shift
	    else
		echo "Unrecognized arg: $1" >&2
		exit 1
	    fi
	    ;;
    esac
done

if [ -z "$input" ] || [ ! -f "$input" ]; then
    echo "Pass one arg, the name of a video file, to scan it for" >&2
    echo "important attributes needed for transcoding." >&2
    echo "" >&2
    echo "Optionally, set a custom cache key with -k/--cache-key." >&2
    echo "This will be used as a path to create cache files in the" >&2
    echo "cache dir, instead of the default path munging." >&2
    exit 1
fi

function debug {
    [[ "$DEBUG" =~ analyze ]] && echo "$1" >&2
    return 0
}

MYDIR="$(dirname "$0")"
input_without_slashes="${input//\//_}"
input_without_leading_dot="${input_without_slashes/#./_}"
CACHEKEY=${cache_key:-$input_without_leading_dot}
CACHEFILE="cache/analyze/$CACHEKEY"
USECACHE=${USECACHE:-true}
[ "$USECACHE" = true ] && {
    debug "Check cache file: $CACHEFILE"
    [ -f "$CACHEFILE" ] && cat "$CACHEFILE" && exit 0
}

tmp_dir="$(mktemp -d)"
trap 'rm -rf -- "$tmp_dir"' EXIT

debug "Sampling input to file"
debug " - $(date)"
$MYDIR/sample.sh -i "$input" -m 2 -f file -o "$tmp_dir/sampled.mkv"
debug " - $(date)"
debug "Analyzing sampled file"
debug " - $(date)"
ffmpeg -y -i "$tmp_dir/sampled.mkv" -filter 'idet,cropdetect=round=2' -f null /dev/null &> "$tmp_dir/analyze_data"
debug " - $(date)"

[ $USECACHE = true ] && mkdir -p "$(dirname "$CACHEFILE")"
if INTERLACED=$("$MYDIR/interlaced.sh" -i "$tmp_dir/analyze_data" -f output -k "$CACHEKEY"); then
    debug "Interlaced: $INTERLACED"
    echo "INTERLACED=$INTERLACED"
    [ $USECACHE = true ] && echo "INTERLACED=$INTERLACED" >> "$CACHEFILE"
else
    debug "Interlace detection failed, but continuing, since it could be set manually"
fi
if CROPPING=$("$MYDIR/crop.sh" -i "$tmp_dir/analyze_data" -f output); then
    debug "Cropping: $CROPPING"
    echo "CROPPING=$CROPPING"
    [ $USECACHE = true ] && echo "CROPPING=$CROPPING" >> "$CACHEFILE"
else
    debug "Crop detect failed, but continuing, since it could be set manually"
fi
