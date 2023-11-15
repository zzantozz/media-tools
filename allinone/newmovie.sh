#!/bin/bash

# Purpose: to make it easy to create a new movie config.
#
# This script should take a ripped dir name to inspect and the proper name of the movie in it. Then magic.
# I'm not sure exactly what, but it should certainly create the movie dir and "main" file. After that, it
# could step through each file in the input dir and prompt for details of each. If it prompts for input,
# it should show the ffprobe streams. Default to all streams. Also show list of valid Plex labels for extras.
# Maybe even offer it as a choice and fill in automatically.

base_dir="/mnt/d/ripping"
config_dir="/home/ryan/media-tools/allinone/data/config"

die() {
  echo "ERROR: $1" >&2
  exit 1
}

usage() {
  echo "Usage: $0 -i <input name> -n <movie name> [-b <base dir>] [-c <config dir>]" >&2
  exit 1
}

while getopts "i:n:b:c:" opt; do
  case "$opt" in
    i)
      input_name="$OPTARG"
      ;;
    n)
      movie_name="$OPTARG"
      ;;
    b)
      base_dir="$OPTARG"
      ;;
    c)
      config_dir="$OPTARG"
      ;;
  esac
done

if [ -z "$input_name" ] || [ -z "$movie_name" ]; then
  usage
fi

if [ -d "$input_name" ]; then
  input_dir="$input_name"
elif [ -d "$base_dir/$input_name" ]; then
  input_dir="$base_dir/$input_name"
else
  die "input name should be path to a ripped movie dir or name of a dir in the base dir, was: $input_name"
fi

if ! ([ -d "$config_dir" ] && [ "config" = "$(basename "$config_dir")" ] && [ "data" = "$(basename "$(dirname "$config_dir")")" ]); then
  die "config dir should point at a config dir in the media toolset, was: $config_dir"
fi

ripped_name="$(basename "$input_dir")"
movie_config="$config_dir/$ripped_name"
mkdir -p "$movie_config"
echo "MAIN_NAME=\"$movie_name\"" > "$movie_config/main"

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
  select t in "Main Feature" "Behind The Scenes" "Deleted Scenes" Featurettes Interviews Scenes Shorts Trailers Other "skip it"; do
    if [ "$t" = "skip it" ]; then
      break
    fi
    config_file="$movie_config/$(basename "$f")"
    if [ "$t" = "Main Feature" ]; then
      out_name="$movie_name.mkv"
    else
      read -p "Enter name: $t/" answer
      out_name="$t/$answer.mkv"
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

