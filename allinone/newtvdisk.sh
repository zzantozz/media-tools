#!/bin/bash

# Purpose: make it easy to create configs for a new disk of a tv show.
#
# Similar to newmovie.sh, but for tv shows. I'm not sure whether it should be per disk, per season, per
# show, or what. I'll start with per disk and see what happens.
#
# Note: For special features, it currently puts them in season 0 as episode ${season}${disk} - <name>,
# where you're prompted for the name. This fits somewhat in Plex's tv special scheme. There has to
# be a better way to do this...

config_dir="/home/ryan/media-tools/allinone/data/config"

die() {
  echo "ERROR: $1" >&2
  exit 1
}

usage() {
  echo "Usage: $0 -i <input name> -n <show name> [-c <config dir>]" >&2
  exit 1
}

while getopts "i:n:b:c:" opt; do
  case "$opt" in
    i)
      input_name="$OPTARG"
      ;;
    n)
      show_name="$OPTARG"
      ;;
    c)
      config_dir="$OPTARG"
      ;;
  esac
done

if [ -z "$input_name" ] || [ -z "$show_name" ]; then
  usage
fi

if [ -d "$input_name" ]; then
  input_dir="$input_name"
fi

if ! ([ -d "$config_dir" ] && [ "config" = "$(basename "$config_dir")" ] && [ "data" = "$(basename "$(dirname "$config_dir")")" ]); then
  die "config dir should point at a config dir in the media toolset, was: $config_dir"
fi

# Expect tv show structure and parse some info from it. Season and disk is usually numeric. Exceptions: season can be like "3.5" (BSG).
# Disks can be like "1A" and "1B" (House).
echo "input dir: $input_dir"
[[ "$input_dir" =~ (([^/]+)/Season\ ([0-9\.]+)/Disk\ ([0-9AB]+)) ]] || die "Couldn't parse season and disk from input name"
rel_path="${BASH_REMATCH[1]}"
show="${BASH_REMATCH[2]}"
season="${BASH_REMATCH[3]}"
disk="${BASH_REMATCH[4]}"
echo "Discovered from input: show=$show season=$season disk=$disk rel_path=$rel_path"

# Figure out where to put the configs
show_config_dir="$config_dir/$show"
main_config="$show_config_dir/main"
echo -e "configs:\n  show: $show_config_dir\n  main: $main_config"

# Ensure main file exists with correct content
mkdir -p "$show_config_dir"
if [ -f "$main_config" ]; then
  grep "MAIN_NAME=\"$show_name\"" "$main_config" || die "Show name mismatch. Expected $show_name, but main has $(cat "$main_config")"
else
  echo "MAIN_NAME=\"$show_name\"" > "$main_config"
fi

probe() {
  PROBE_RESULT="$(ffprobe -probesize 42M -i "$1" 2>&1 | grep Stream)"
}

for f in "$input_dir"/*; do
  echo ""
  echo "Details of $f"
  echo ""
  probe "$f"
  echo "$PROBE_RESULT"
  echo ""
  echo "What is this?"
  select t in "Episode" "Special Episode" "Special Feature" "skip it"; do
    if [ "$t" = "skip it" ]; then
      break
    fi
    disk_number="$(printf %0.2d "$disk")"
    season_number="$(printf %0.2d "$season")"
    if [ "$t" = "Episode" ]; then
      read -p "Enter episode number: " answer
      episode_number="$(printf %0.2d "$answer")"
      out_name="$show_name s${season_number}e${episode_number}.mkv"
    elif [ "$t" = "Special Episode" ]; then
      read -p "Enter episode number: " answer
      episode_number="$(printf %0.2d "$answer")"
      out_name="$show_name s00e${episode_number}.mkv"
    elif [ "$t" = "Special Feature" ]; then
      read -p "Name: " answer
      out_name="$show_name s00e${season_number}${disk_number} - $answer.mkv"
    else
      echo "Not yet written"
      exit 1
    fi
    read -p "Keep (a)ll streams or (s)elect streams? [A/s] " answer
    if [ "$answer" = "" ] || [ "$answer" = a ]; then
      keep_streams=all
    else
      read -p "Enter space-separated streams to keep: " -a answer
      keep_streams=()
      for s in "${answer[@]}"; do
        keep_streams+=("0:$s")
      done
      keep_streams="(${keep_streams[@]})"
    fi
    read -p "Encode '$f' as '$out_name' with streams $keep_streams? [Y/n] " answer
    if [ -z "$answer" ] || [ "$answer" = y ]; then
      config_file="$config_dir/$rel_path/$(basename "$f")"
      mkdir -p "$(dirname "$config_file")"
      echo "Writing to $config_file"
      echo "OUTPUTNAME=\"$out_name\"" > "$config_file"
      echo "KEEP_STREAMS=$keep_streams" >> "$config_file"
      read -p "Any extras? [y/N] " answer
      if [ "$answer" = y ]; then
        echo "Enter extra lines to append to config, followed by ^D"
        extras=$(</dev/stdin)
        echo "$extras" >> "$config_file"
      fi
      break
    fi
  done
done

