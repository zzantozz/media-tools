#!/bin/bash

# Rips a disk with makemkvcon.
#
# This stores the disk info (makemkvcon info) and titles in a directory named according to the disk
# name found in the info. It's the first step to ripping and transcoding a disk.

script_dir="$(cd "$(dirname "$0")" && pwd)"
base_output_dir="/l/ripping"
makemkvcon_path="/c/Program Files (x86)/MakeMKV/makemkvcon"

usage() {
  echo "Usage: $0 -f [-b <base output dir>] [-m <makemkvcon path>]" >&2
  echo ""
  echo "Rips a disk with makemkvcon. First, it reads the disk info with the 'info' command. It uses"
  echo "the info to detect the disk name. Then, it creates an output directory, moves the info there"
  echo "for future use, and rips the titles to the same directory."
  echo ""
  echo "Options:"
  echo "  -f"
  echo "    Really run. Since this script has no required options otherwise, this flag is required"
  echo "    to make it actually run. Otherwise, you just get the usage info."
  echo ""
  echo "  -b <base output dir>"
  echo "    Sets the base output directory, inside of which the ripping dirs are created."
  echo ""
  echo "  -m <makemkvcon path>"
  echo "    Sets the path to makemkvcon."
  exit 1
}

die() {
  echo "ERROR: $1" >&2
  usage
}

while getopts "fb:m:" opt; do
  case "$opt" in
    f)
      really_run=true
      ;;
    b)
      base_output_dir="$OPTARG"
      ;;
    m)
      makemkvcon_path="$OPTARG"
      ;;
    *)
      usage
      ;;
  esac
done

[ -d "$base_output_dir" ] || die "base output dir must be a directory, was '$base_output_dir'"
[ -f "$makemkvcon_path" ] || die "makemkvcon not found at '$makemkvcon_path'"
[ "$really_run" = true ] || usage

tmp_info="$(mktemp)"
trap 'rm -f "$tmp_info"' EXIT

"$makemkvcon_path" -r info disc:0 >"$tmp_info"

# From a cursory examination of some disk info, it seems the name of the disk is stored in CINFO with an index of 2, 30, and 32. If I look in all of
# them, hopefully I'll always find a good value somewhere.
for n in 2 30 32; do
  cinfo="$(grep "CINFO:$n,0," "$tmp_info")"
  if [[ "$cinfo" =~ ^CINFO:$n,0,\"(.+)\" ]]; then
    disk_name="${BASH_REMATCH[1]}"
    [ -n "$disk_name" ] && break
  fi
done

# Show title overlap early, so I can see if the rip needs to be adjusted
bash "$script_dir/check-title-overlap.sh" "$tmp_info"

[ -n "$disk_name" ] || die "Unable to find disk name in disk info"
disk_name="${disk_name/\'/}"
disk_name="${disk_name/:/ -}"
echo
echo "Disk name will be '$disk_name'"
echo

got_info=false
tracks=all

while [ "$got_info" = false ]; do
  read -p "Change [d]isk name? Select [t]itles to exclude? Or ready to [g]o? [d/t/G] " answer

  if [ -z "$answer" ] || [ "$answer" = g ]; then
    got_info=true
  elif [ "$answer" = d ]; then
    read -p "New disk name: " disk_name
  elif [ "$answer" = t ]; then
    read -p "Titles to exlude (space separated): " titles
    echo "Not yet written - maybe not possible?"
    exit 1
  fi
done

# Create the output dir and put everything in it
output_dir="$base_output_dir/$disk_name"
mkdir -p "$output_dir" || die "Failed to create output dir '$output_dir'"
mv "$tmp_info" "$output_dir/_info"
"$makemkvcon_path" mkv disc:0 all "$output_dir"

# This seems like a good place to spit out title overlap. In the future, maybe automate more around this, like prompting to omit titles if they overlap.
bash "$script_dir/check-title-overlap.sh" "$output_dir/_info"
