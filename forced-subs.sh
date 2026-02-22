#!/bin/bash

script_dir="$(cd "$(dirname "$0")" && pwd)"

source "$script_dir/allinone/config"
source "$script_dir/allinone/utils"

debug() {
  if [[ "$DEBUG" =~ forced-subs ]]; then
    echo -e "$1" >&2
  fi
}

usage() {
  echo "USAGE"
  echo "    Usage: $0 -i <mkv-file> [-t <threshold>]"
  echo
  echo "DESCRIPTION"
  echo "    Inspects an MKV file's subtitle streams to identify ones that should be forced. It determines this by"
  echo "    looking for a subtitle stream with significantly fewer frames than another. By default, it looks for a"
  echo "    stream that's 10% or smaller in size than other streams. You can adjust this with the '-t' option."
  echo
  echo "OPTIONS"
  echo "    -i"
  echo "        Set the input file."
  echo
  echo "    -t"
  echo "        Set the comparison threshold. Defaults to 10%."
}

threshold=10

while getopts ":i:t:" opt; do
  case "$opt" in
    i)
      input="$OPTARG"
      ;;
    t)
      threshold="$OPTARG"
      ;;
    *)
      usage
      exit 1
  esac
done

[ -n "$input" ] || die "Set input file with -i"
[ -f "$input" ] || die "Input doesn't exit: '$input'"

debug "Looking for forced subs in '$input'"
debug "  forced sub stream length threshold: ${threshold}%"

# Get details of subtitle streams. From looking through ffprobe output, it looks like the NUMBER_OF_FRAMES-eng and
# NUMBER_OF_BYTES-eng "tags" are the best bet. If these are missing, I'll have to figure out something else.
# Sample output from Rise of Skywalker, with two sub streams, second is alien language:
# 4,3790,36950983
# 5,4,18149
raw_data="$(ffprobe -i "$input" -v error -select_streams s -show_entries stream=index:stream_tags=NUMBER_OF_FRAMES-eng,NUMBER_OF_BYTES-eng -of csv=p=0)" || \
  die "Failed to get stream data"

[ -z "${raw_data//[[:blank:]]/}" ] && {
  debug "No subs detected means no forced subs"
  echo "none"
  exit 0
}

debug "  raw sub data\n---\n$raw_data\n---"

readarray -t data_lines <<<"$raw_data"
[ "${#data_lines[@]}" -gt 0 ] || die "No subtitle streams found"

indexes=()
frame_counts=()
byte_counts=()

max_frames=0
max_bytes=0
for line in "${data_lines[@]}"; do
  comma_count="$(echo "$line" | tr -cd , | wc -c)"
  # If a tag is missing, it just gets omitted from the output
  [ "$comma_count" -eq 2 ] || die "Didn't get the right number of fields in '$line'"
  # Break down the data
  IFS=, read -r -a stream_data <<<"$line"
  index="${stream_data[0]}"
  frames="${stream_data[1]}"
  bytes="${stream_data[2]}"
  # Now deal with it
  indexes+=("$index")
  frame_counts+=("$frames")
  byte_counts+=("$bytes")
  [ "$frames" -gt "$max_frames" ] && max_frames="$frames"
  [ "$bytes" -gt "$max_bytes" ] && max_bytes="$bytes"
done

debug "  max frames is $max_frames. Max bytes is $max_bytes."

frame_threshold=$((max_frames * threshold / 100))
byte_threshold=$((max_bytes * threshold / 100))

forced=()
for i in "${!indexes[@]}"; do
  ignore=false
  stream_index="${indexes[i]}"
  debug "  check stream $stream_index (subtitle stream $i)"
  frames="${frame_counts[i]}"
  bytes="${byte_counts[i]}"
  if [ "$frames" -lt "$frame_threshold" ]; then
    [ "$bytes" -lt "$byte_threshold" ] || die "frame and byte counts disagree"
    # I've encountered several titles that seem to have duplicate forced subtitle streams. Let's try to avoid those by just letting the
    # first one win.
    if [ "${#forced[@]}" -gt 0 ]; then
      prev_frames="${frame_counts[i-1]}"
      prev_bytes="${byte_counts[i-1]}"
      if [ "$frames" = "$prev_frames" ] && [ "$bytes" = "$prev_bytes" ]; then
	debug "  stream $stream_index appears to be a duplicate of ${indexes[i-1]}, ignoring it"
	ignore=true
      fi
    fi
    [ "$ignore" = false ] && forced+=("$stream_index")
  fi
done

if [ ${#forced[@]} -gt 1 ]; then
  echo "More than one subtitle identified as probable forced. All detected: ${forced[*]}." >&2
  echo "You can diagnose more with:" >&2
  for f in "${forced[@]}"; do
    echo "ffprobe -v error -select_streams $f -read_intervals 0%+#11 -show_entries packet=dts_time -of csv=p=0 '$input' | head -5" >&2
  done
  exit 1
elif [ ${#forced[@]} -eq 1 ]; then
  echo "${forced[0]}"
elif [ ${#forced[@]} -eq 0 ]; then
  echo "none"
fi

#echo "Found ${#forced[@]} likely forced subtitle track(s)."
#read -p "Set forced flag on these tracks? (y/n) " -n 1 -r
#echo
#
#if [[ ! $REPLY =~ ^[Yy]$ ]]; then
#    echo "Aborted."
#    exit 0
#fi
#
# Use mkvpropedit to set forced flag
# (mkvpropedit is part of mkvtoolnix package)
#if ! command -v mkvpropedit &> /dev/null; then
#    echo "ERROR: mkvpropedit not found. Install with: sudo apt install mkvtoolnix"
#    exit 1
#fi
#
#for i in "${FORCED_STREAMS[@]}"; do
#    TRACK_NUM=$((i + 1))  # mkvpropedit uses 1-based track numbers
#    echo "Setting forced flag on track $TRACK_NUM..."
#    echo mkvpropedit "$input" --edit track:s$TRACK_NUM --set flag-forced=1
#done

