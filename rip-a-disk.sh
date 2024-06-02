#!/bin/bash

# Rips a disk with makemkvcon.
#
# This stores the disk info (makemkvcon info) and titles in a directory named according to the disk
# name found in the info. It's the first step to ripping and transcoding a disk.

script_dir="$(cd "$(dirname "$0")" && pwd)"
base_output_dir="${BASE_OUTPUT_DIR:-/l/ripping}"
makemkvcon_path="/c/Program Files (x86)/MakeMKV/makemkvcon64"

usage() {
  echo "Usage: $0 [-f] [-d <disc num>] [-b <base output dir>] [-m <makemkvcon path>]" >&2
  echo ""
  echo "Rips a disk with makemkvcon. First, it reads the disk info with the 'info' command. It uses"
  echo "the info to detect the disk name. Then, it creates an output directory, moves the info there"
  echo "for future use, and rips the titles to the same directory."
  echo ""
  echo "Options:"
  echo "  -f"
  echo "    Don't prompt for input. Use the disk name taken from makemkvcon output."
  echo ""
  echo "  -d"
  echo "    Use the specified device instead of \\Device\\CdRom0 - see makemkvcon f -l for devices."
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

while getopts "fb:d:m:" opt; do
  case "$opt" in
    f)
      force=true
      ;;
    d)
      device="$OPTARG"
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
[ -n "$device" ] || device='\Device\CdRom0'

tmp_info="$(mktemp)"
trap 'rm -f "$tmp_info"' EXIT

echo "Grabbing disk info to $tmp_info"
[ -n "$SKIP_INFO" ] || "$makemkvcon_path" -r --minlength=0 --noscan info "dev:$device" >"$tmp_info"

# From a cursory examination of some disk info, it seems the name of the disk is stored in CINFO with an index of 2, 30, and 32. If I look in all of
# them, hopefully I'll always find a good value somewhere.
for n in 2 30 32; do
  cinfo="$(grep "CINFO:$n,0," "$tmp_info")"
  if [[ "$cinfo" =~ ^CINFO:$n,0,\"(.+)\" ]]; then
    disk_name="${BASH_REMATCH[1]}"
    [ -n "$disk_name" ] && break
  fi
done

#[ -n "$disk_name" ] || die "Unable to find disk name in disk info"
disk_name="${disk_name/\'/}"
disk_name="${disk_name/’/}"
disk_name="${disk_name//:/ -}"
disk_name="$(echo "$disk_name" | tr -s ' ')"
echo
echo "Disk name will be '$disk_name'"
echo

got_info="${force:-false}"
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

[ -n "$disk_name" ] || die "Disk name can't be empty"

# Create the output dir and put everything in it
output_dir="$base_output_dir/$disk_name"
mkdir -p "$output_dir" || die "Failed to create output dir '$output_dir'"
mv "$tmp_info" "$output_dir/_info"
[ -n "$SKIP_INFO" ] || "$makemkvcon_path" -r --minlength=30 --noscan info "dev:$device" >"$output_dir/_info_30"
begin_rip=$(date +%s)
[ -n "$ONLY_INFO" ] || time "$makemkvcon_path" --minlength=30 --noscan mkv "dev:$device" all "$output_dir"
end_rip=$(date +%s)

# Figure out rough completion rate. I use this in Git bash in windows, so bc isn't available, and we have to
# account for plain int division with truncation by adding half the divisor to the dividend.
size=$(du "$output_dir" | awk '{print $1}')
size_kb=$(( size ))
elapsed=$(( end_rip-begin_rip ))
elapsed_min=$(( (elapsed+30)/60 ))
elapsed_sec=$(( elapsed-(elapsed_min*60) ))
rip_rate=$(( (size_kb+(elapsed/2))/elapsed ))
printf "Took %d (%02d:%02d) to rip %d KB at %d KB/s\n" "$elapsed" "$elapsed_min" "$elapsed_sec" "$size_kb" "$rip_rate"

# This seems like a good place to spit out title overlap. In the future, maybe automate more around this, like prompting to omit titles if they overlap.
bash "$script_dir/check-title-overlap.sh" "$output_dir/_info_30"

# Make a sound so I know it's done!
echo -en "\007"
