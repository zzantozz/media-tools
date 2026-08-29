# New iteration of sampling script.
#
# This script exists so that I can do some analysis on movies without having to read the entire input file.
# The idea is that if I take enough representative samples of a movie, I can figure out the things I need
# in a much shorter time: things like interlacing and cropping settings. To be an accurate sample, it should
# be sure to include some of the initial and final credits because they can be filmed differently.
#
# This is a new version because the old one started failing on 4K and larger features because of the way it
# was implemented. By opening the input multiple times, it used a ton of memory and would crash.
#
# The original version supported either sampling an incoming stream on stdin or reading an input file. In
# order to achieve low memory and the speed that's the whole point of this effort, this script only allows
# a file as input because it needs to carve chunks out of the file on demand, instead of processing the
# whole thing as a stream one time.

#!/bin/bash -e

while [ $# -gt 0 ]; do
    key="$1"
    case "$key" in
        -i|--input)
            input="$2"
            shift 2
            ;;
        -o|--output)
            output="$2"
            shift 2
            ;;
        -m|--min-length)
            min_length="$2"
            shift 2
            ;;
        -t|--target-chunks)
            target_chunks="$2"
            shift 2
            ;;
        -l|--sample-length)
            sample_length="$2"
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
[ -z "$min_length" ] && min_length=30
[ -z "$target_chunks" ] && target_chunks=100
[ -z "$sample_length" ] && sample_length=2

[ "$target_chunks" -gt 1 ] || die "You need to take more than one chunk."

function debug {
    [[ "$DEBUG" =~ sample ]] && echo "$1" >&2
    return 0
}

script_dir="$(cd "$(dirname "$0")" && pwd)"

IFS=':.' read -r h m s fraction <<<"$(ffprobe -v error -select_streams v:0 -show_entries stream_tags=DURATION-eng,DURATION -of default=noprint_wrappers=1:nokey=1 "$input")"
h="10#$h"
m="10#$m"
s="10#$s"
debug "h: $h m: $m s: $s rest: $fraction"
total_secs=$((h*3600 + m*60 + s))

# If shorter than the minimum just do the whole thing.
if [ $total_secs -lt $((min_length*60)) ]; then
    debug "Input is less than min length of $min_length minutes, so not sampling"
    cmd=(ffmpeg -nostdin -i "$input" -map 0:0 -c copy)
    cmd+=(-f matroska)
    cmd+=("$output")
    if [[ "$DEBUG" =~ sample ]]; then
        for arg in "${cmd[@]}"; do
            echo -n "\"${arg//\"/\\\"}\" " >&2
        done
        echo
        "${cmd[@]}"
    else
        "${cmd[@]}" 2>/dev/null
    fi
else
    tmp_dir=$(mktemp -d)
    trap 'rm -rf "$tmp_dir"' EXIT

    concat_list="$tmp_dir/concat_list.txt"
    > "$concat_list"

    # Compute usable range so samples (of sample_length) fit within total_secs.
    usable_secs=$(echo "$total_secs - $sample_length" | bc)

    if (( $(echo "$usable_secs < 0" | bc -l) )); then
        echo "Error: sample_length is longer than total_secs" >&2
        exit 1
    fi

    step=$(echo "$usable_secs / ($target_chunks - 1)" | bc -l)
    debug "Taking $target_chunks samples of length ${sample_length}s"
    for (( i=0; i<target_chunks; i++ )); do
        start=$(echo "$step * $i" | bc -l)
        sample_file="$tmp_dir/sample_$(printf '%03d' "$i").mkv"
        ffmpeg -y -nostdin -ss "$start" -i "$input" -t "$sample_length" -c copy -map 0:0 -avoid_negative_ts make_zero "$sample_file" &>/dev/null
        # Use absolute path in the concat list.
        printf "file '%s'\n" "$sample_file" >> "$concat_list"
    done
    debug "Concatting all samples"
    ffmpeg -y -f concat -safe 0 -i "$concat_list" -map 0:0 -c copy -f matroska "$output" &>/dev/null
fi
