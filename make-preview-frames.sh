#!/bin/bash

# Purpose: grab a handful of frames from all the titles of a ripped disk so I can quickly decide whether it's
# actual content or should be thrown away. Point it at a disk and an output directory, and it creates a folder
# for each title containing some frames grabbed from the title. When viewed in a typical file explorer as large
# icons, it should easily show what kind of title it is.

usage() {
  cat <<EOF
Usage: $0 -i <input dir> -o <output dir>

  <input dir>  - A directory where a disk was ripped that contains video titles
  <output dir> - A directory to write captured frames to
EOF
  exit 1
}

while getopts "i:o:" opt; do
  case "$opt" in
    i)
      input="$OPTARG"
      ;;
    o)
      output="$OPTARG"
      ;;
    *)
      echo
      usage
      exit 1
      ;;
  esac
done

die() {
  echo "ERROR: $1" >&2
  exit 1
}

[ -d "$input" ] || die "Input dir must be a directory; was '$input'"
[ -n "$output" ] || die "You must set an output directory"

mkdir -p "$output"
for f in "$input"/*; do
  echo "Processing $f"
#  output_dir="$output/$(basename "$f")"
  ffmpeg -i "$f" -map 0:0 -filter 'fps=fps=1/15' -frames:v 20 "$output/$(basename "$f")-%03d.png"
done
