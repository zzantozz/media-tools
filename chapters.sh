#!/bin/bash

# Reads chapters from an input video and outputs details about them to stdout.
# Initially, it just writes out the chapter start times. I could add options to
# enable different outputs.

chapter_num=0
chapter_starts=()
chapter_ends=()

while getopts "i:" opt; do
  case "$opt" in
    i)
      input="$OPTARG"
      ;;
    *)
      echo "Invalid usage!"
      ;;
  esac
done

debug() {
  [[ "$DEBUG" =~ chapters ]] && {
    echo "$1" >&2
  }
}

[ -f "$input" ] || {
  echo "Input is not a file: $input" >&2
  echo "Specify an input with -i" >&2
  exit 1
}

while read -r line; do
  if [[ "$line" =~ \[CHAPTER\] ]]; then
    chapter_num=$((chapter_num+1))
    debug "Found ch $chapter_num"
  fi
  if [[ "$line" =~ start_time=(.*) ]]; then
    start="${BASH_REMATCH[1]}"
    debug "Found start: $start"
    chapter_starts[$chapter_num]="$start"
  fi
  if [[ "$line" =~ end_time=(.*) ]]; then
    end="${BASH_REMATCH[1]}"
    debug "Found end: $end"
    chapter_ends[$chapter_num]="$end"
  fi
done < <(ffprobe -hide_banner -i "$input" -show_chapters -sexagesimal -v error)
echo "${chapter_starts[*]}"

