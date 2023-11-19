#!/bin/bash

# Purpose: to make it easy to create a new movie config.
#
# This script takes a ripped dir name to inspect and the proper name of the movie in it. It creates the "main"
# movie config file, and it steps through each file in the input dir and prompts for details of each. Default
# to all streams. After collecting information about the title, it writes out a data file for it.

config_dir="/home/ryan/media-tools/allinone/data/config"

die() {
  echo "ERROR: $1" >&2
  exit 1
}

usage() {
  echo "Usage: $0 -i <input name> -n <movie name> [-c <config dir>]" >&2
  exit 1
}

while getopts "i:n:b:c:" opt; do
  case "$opt" in
    i)
      input_dir="$OPTARG"
      ;;
    n)
      movie_name="$OPTARG"
      ;;
    c)
      config_dir="$OPTARG"
      ;;
  esac
done

if [ -z "$input_name" ] || [ -z "$movie_name" ]; then
  usage
fi

if ! [ -d "$input_dir" ]; then
  die "input dir should be path to a ripped movie dir, was: $input_name"
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

