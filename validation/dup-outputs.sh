#!/bin/bash

# Finds output files with duplicate mappings. This means multiple inputs are mapped to the same output file.
#
# It does that by running the encode script in ONLY_MAP mode and looking for duplicates in the output field.
# This means it's limited to detecting duplicates for input files that are in scope for the encode. If a media
# drive isn't currently mounted:
echo " ***"
echo "WARNING: Won't find duplicates mapped from unavailable input files! All input drives/files have to be mounted" >&2
echo "WARNING: for a comprehensive result!" >&2
echo " ***"
# This is due to the complexity of mapping inputs to outputs. A lot of the logic is embedded in the encode script.

script_dir="$(cd "$(dirname "$0")" && pwd)"
. "$script_dir/../allinone/utils"

export WORKDIR="$(mktemp -d)"
tmp_file="$(mktemp)"
debug "WORKDIR=$WORKDIR"
debug "tmp_file=$tmp_file"
trap "rm -rf '$WORKDIR'; rm -rf '$tmp_file';" EXIT

echo "Scanning inputs."

ONLY_MAP=true "$script_dir/../allinone/encode.sh" &>"$tmp_file" || {
  err="$(cat "$tmp_file" | head -5)"
  msg="$(printf "Encode script failed. Error follows. See tmp file for full output: '%s'\n%s\n" "$tmp_file" "$err")"
  die "$msg"
}

dups_raw="$(cat "$tmp_file" | grep '^IN:' | sed 's/^IN:.*OUT: //' | sort | uniq -c | grep -v '^      1' | sed 's/^[ 0-9]*//')"
dups=()
while read -r output_path; do
  # Somehow a blank line can creep in
  [ -z "$output_path" ] || dups+=("$output_path")
done <<<"$dups_raw"

if [ "${#dups[@]}" -gt 0 ]; then
  echo "Duplicate mapped outputs"
  for dup in "${dups[@]}"; do
    echo " out: $dup"
    grep -F "OUT: $dup" "$tmp_file" | sed -r 's/^IN: (.*) OUT:.*/   in: \1/'
  done
else
  echo "No dups found!"
fi

work_items="$(ls -1 "$WORKDIR" | wc -l)"
if [ "$work_items" -gt 0 ]; then
  echo "ERROR! No actual work should have been done!"
  exit 1
fi
