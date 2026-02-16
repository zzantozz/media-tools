#!/bin/bash

. allinone/utils

usage() {
  echo "USAGE"
  echo "    Usage: <cmd producing paths> | $0 -t"
  echo
  echo "DESCRIPTION"
  echo "    Gets information about forced subs in video files. This script reads paths from stdin. For each path, it"
  echo "    checks if it has forced sub and prints the path in red if not, green if so. It also prints the stream index"
  echo "    of the subs in question if found."
  echo
  echo "    With -t, also shows the timestamps of some packets in the suspected stream to make it easier to find and"
  echo "    verify them. This can be slow depending on where they occur in the input."
  echo
  echo "OPTIONS"
  echo "    -h"
  echo "        Show this usage info and exit."
  echo
  echo "    -s"
  echo "        Show summary table. Writes final lists of inputs that do and do not have forced subs. Useful for"
  echo "        sending to an AI to see what it thinks of the results."
  echo
  echo "    -t"
  echo "        Show timestamps of the first few frames in suspected forced sub streams. May be slow, depending on"
  echo "        where the subs occur in the input."
}

while getopts "hts" opt; do
  case "$opt" in
    h)
      usage
      exit 0
      ;;
    t)
      show_frame_times=true
      ;;
    s)
      summary=true
      ;;
    *)
      die "Unrecognized arg: $OPTARG"
      ;;
  esac
done

with=()
without=()

while read -r line; do
  abs_path="$line"
  subs="$(./forced-subs.sh -i "$abs_path")"
  printf ' -> '
  if [ "$subs" = none ] || [ -z "${subs//[[:blank:]]/}" ]; then
    printf "$red"
    without+=("$abs_path")
  else
    printf "$green"
    with+=("$abs_path")
  fi
  printf "%s -- %s\n" "$abs_path" "$subs"
  printf "$nc"
  if [ "$show_frame_times" = true ] && [[ "$subs" =~ [0-9][0-9]* ]]; then
    # Show dts_time of packets in the stream in csv format, which puts it in a single line. I have no idea what the
    # read_intervals option does.
    ffprobe -v error -select_streams "$subs" -read_intervals 0%+#11 -show_entries packet=dts_time -of csv=p=0 "$abs_path" | head -5
  fi
done

if [ "$summary" = true ]; then
  echo "Yes:"
  for f in "${with[@]}"; do
    echo "  $f"
  done
  echo
  echo "No:"
  for f in "${without[@]}"; do
    echo "  $f"
  done
fi
