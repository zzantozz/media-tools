#!/bin/bash

# Checks MakeMKV info output to find titles with overlapping segments.
# 
# For example, often a DVD or Bluray will have one title containing all the deleted scenes but also have
# every deleted scene as its own title. This will find things like that so you can easily identify what
# to do with them.
#
# Call with the output of 'makemkvcon -r info disc:0'. You can provide the output either on stdin or by
# calling this script with the name of a file that contains the output.

contains() { arr=($1); item="$2"; for x in "${arr[@]}"; do if [ "$x" = "$item" ]; then return 0; fi; done; return 1; }
contains_all() { items=($2); for item in "${items[@]}"; do if ! contains "$1" "$item"; then return 1; fi; done; return 0; }

segment_map=()
duration_map=()
while read -r line; do
  if [[ "$line" =~ ^TINFO:(.+),26,0,\"(.*)\" ]]; then
    title="${BASH_REMATCH[1]}"
    segments=$(echo "${BASH_REMATCH[2]}" | tr , ' ')
    segment_map["$title"]="$segments"
  fi
  if [[ "$line" =~ ^TINFO:(.+),9,0,\"(.*)\" ]]; then
    title="${BASH_REMATCH[1]}"
    time="${BASH_REMATCH[2]}"
    duration_map["$title"]="$time"
  fi
done < "${1:-/dev/stdin}"

echo "Got ${#segment_map[@]} titles"

for title in "${!segment_map[@]}"; do
  for k in "${!segment_map[@]}"; do
    if [ "$k" = "$title" ]; then
      continue
    fi
    if [ "${segment_map[$k]}" = "${segment_map[$title]}" ]; then
      echo "title $title is the same as title $k - duration ${duration_map["$title"]}"
    elif contains_all "${segment_map[$k]}" "${segment_map[$title]}"; then
      echo "title $title (${duration_map["$title"]}) is fully contained by title $k (${duration_map["$k"]})"
    fi
  done
done
