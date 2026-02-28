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
  echo "    -a"
  echo "        Audit mode. After determining if a title *should* have forced subs, check if it does."
  echo
  echo "    -s"
  echo "        Show summary table. Writes final lists of inputs that do and do not have forced subs. Useful for"
  echo "        sending to an AI to see what it thinks of the results."
  echo
  echo "    -t"
  echo "        Show timestamps of the first few frames in suspected forced sub streams. May be slow, depending on"
  echo "        where the subs occur in the input."
}

while getopts "hats" opt; do
  case "$opt" in
    h)
      usage
      exit 0
      ;;
    a)
      audit=true
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
  desired_forced="$(./forced-subs.sh -i "$abs_path")"
  if [[ "$desired_forced" =~ [0-9][0-9]* ]]; then
    should_force=true
    with+=("$abs_path")
  else
    should_force=false
    without+=("$abs_path")
  fi
  printf ' -> '
  if [ "$audit" = true ]; then
    # Get forced status of sub streams. Example:
    # 5|0
    # 6|1
    # 7|0
    ffprobe -v error -select_streams s -show_entries stream=index:disposition=forced -of compact=p=0:nk=1 "$abs_path" | \
    while read -r line; do
      IFS='|' read -r -a args <<<"$line"
      stream_index="${args[0]}"
      forced="${args[1]}"
      if [ "$forced" = 1 ]; then
        if [ -n "$existing_forced_stream" ]; then
            die "Found two existing forced streams. Not sure what to do! All forced dispositions: ${lines[*]}"
        fi
        existing_forced_stream="$stream_index"
      fi
    done
    # Check if the suspected forced stream is the same as the existing one
    case "$should_force:$existing_forced_stream" in
      # Good if the one we want is already forced, or if we don't want anything forced and it isn't
      true:$desired_forced|false:) printf "$green" ;;
      # Bad if anything else
      *) printf "$red" ;;
    esac
  else
    # Not audit mode, just highlight the files that we think should have forced subs
    if [ "$should_force" = true ]; then
      printf "$green"
    else
      printf "$red"
    fi
  fi
  printf "%s -- %s\n" "$abs_path" "$desired_forced"
  printf "$nc"
  if [ "$show_frame_times" = true ] && [[ "$desired_forced" =~ [0-9][0-9]* ]]; then
    # Show dts_time of packets in the stream in csv format, which puts it in a single line. I have no idea what the
    # read_intervals option does.
    ffprobe -v error -select_streams "$desired_forced" -read_intervals 0%+#11 -show_entries packet=dts_time -of csv=p=0 "$abs_path" | head -10
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
