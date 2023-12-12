#!/bin/bash

usage() {
  cat <<EOF
Usage: $0 [-h] [-i <input file>]

Reads output of 'makemkvcon -r info' from stdin or a given file and parses it.

This script acts as a streaming parser, emitting "events" for each item it encounters.
It does this by calling functions to handle the events. If no such function is defined,
nothing happens. Thus, if you run this script in a fresh shell, it will appear to do
nothing.

Set DEBUG to a non-empty value to see the events being emitted.

To handle an event, define a function named "handle_\${event_name}", such as

handle_start_tinfo() {
  echo "I'm starting a new title!"
}

To avoid having to export each handler function, I recommend sourcing this script instead
of invoking it directly. To support doing that, you can also specify the input file with
the env var INPUT.

The "start" and "end" events carry no additional data.

The data-carrying events pass said data to the handler function as separate arguments.
EOF
  exit 1
}

while [ $# -gt 0 ]; do
  key="$1"
  case "$key" in
    -i|--input)
      input="$2"
      shift 2
      ;;
    -h|--help)
      usage
      ;;
    *)
      usage
      ;;
  esac
done

input="${INPUT:-$input}"

die() {
  echo "ERROR: $1" >&2
  exit 1
}

debug() {
  if [ -n "$DEBUG" ]; then
    echo "$1"
  fi
}

emit() {
  event_type="$1"
  shift 1
  function_name="handle_${event_type}"
  if [ "$(type -t "$function_name")" == function ]; then
    "$function_name" "$@" || die "Handler function failed"
  else
    debug "Skipping event with no handler: $event_type"
  fi
}

line_type() {
  line_type="$1"
  if [ "$last_line_type" != "$line_type" ]; then
    if [ -n "$last_line_type" ]; then
      emit "end_${last_line_type}"
    fi
    if [ -n "$line_type" ]; then
      emit "start_${line_type}"
    fi
  fi
  last_line_type="$line_type"
}

title_number() {
  title_number="$1"
  if [ "$last_title_number" != "$title_number" ]; then
    if [ -n "$last_title_number" ]; then
      emit "end_title" "${last_title_number}"
    fi
    if [ -n "$title_number" ]; then
      emit "start_title" "${title_number}"
    fi
  fi
  last_title_number="$title_number"
}

declare -a cinfo_type
cinfo_type[1]="disc_type"
cinfo_type[2]="name1"
cinfo_type[30]="name2"
cinfo_type[32]="name3"

emit_cinfo() {
  line_type cinfo
  info_type="${cinfo_type[$2]:-UNKNOWN}"
  other="$3"
  value="$4"
  emit cinfo "$info_type" "$other" "$value"
}

declare -a tinfo_type
tinfo_type[16]="mpls_name"
tinfo_type[9]="duration"
tinfo_type[26]="segments"
tinfo_type[8]="chapter_count"
tinfo_type[10]="size_readable"
tinfo_type[11]="size_bytes"
tinfo_type[29]="language_readable"
tinfo_type[28]="language_code"
tinfo_type[27]="file_name"

emit_tinfo() {
  line_type tinfo
  title_num="$2"
  title_number "$title_num"
  info_type="${tinfo_type[$3]:-UNKNOWN}"
  other="$4"
  value="$5"
  emit tinfo "$title_num" "$info_type" "$other" "$value"
}

emit_sinfo() {
  line_type sinfo
  emit sinfo "$@"
}

unset last_line_type
unset last_title_number
while read -r line; do
  if [[ "$line" =~ ^SINFO:(.+),(.+),(.+),(.+),\"(.*)\" ]]; then
    emit_sinfo "${BASH_REMATCH[@]}"
  elif [[ "$line" =~ ^TINFO:(.+),(.+),(.+),\"(.*)\" ]]; then
    emit_tinfo "${BASH_REMATCH[@]}"
  elif [[ "$line" =~ ^CINFO:(.+),(.+),\"(.*)\" ]]; then
    emit_cinfo "${BASH_REMATCH[@]}"
  elif [[ "$line" =~ ^TCOUNT:(.+) ]]; then
    emit tcount "${BASH_REMATCH[1]}"
  else
    debug "Unparsed line: $line"
  fi
done < "${input:-/dev/stdin}"
# Force final end
line_type ""
title_number ""
