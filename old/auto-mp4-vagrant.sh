#!/bin/bash

set -e

echo "WARNING   This is a real bash script that must be run inside a linux VM"
echo "WARNING   that has handbrake-cli and appropriate encoders installed."

ROOT_DIR="/vagrant_data"
SOURCE_DIR="$ROOT_DIR/__mp4-these"
DEST_DIR="$ROOT_DIR/__freshly-encoded"

# Account for spaces in file names by setting 'for loops separator' with IFS
IFS=$(echo -en "\n\b")

for f in `ls -1 $SOURCE_DIR`; do
  echo "Processing $SOURCE_DIR/$f"
  BASE_NAME="${f%.*}"
  #HANDBRAKE_OPTIONS="--encoder x264 --decomb bob --quality 20 --aencoder copy -i \"$SOURCE_DIR/$f\" -o \"$DEST_DIR/$BASE_NAME.mkv\""
  echo "  executing handbrake cli, but i can't get it to run from a preset cmd variable"
  #echo "  output will be appended to auto-mp4.log"
  echo "  *******************************************"
  # Notes:
  # - write to mkv because multiple audio and subtitle tracks
  # - decomb bob seems the best for any input destined for non-interlaced output
  # - quality 20 seems good for dvd or blu-ray destined for 1080p output; reportedly,
  #   you can get away with quality 22 for bluray
  # - the --*-lang-list options paired with the --all-* makes sure I get all english
  #   audio and subtitle tracks
  HandBrakeCLI \
    --input "$SOURCE_DIR/$f" \
    --output "$DEST_DIR/$BASE_NAME.mkv" \
    --encoder x264 \
    --decomb bob \
    --quality 20 \
    --aencoder copy \
    --audio-lang-list eng \
    --all-audio \
    --subtitle-lang-list eng \
    --all-subtitles
  echo "  *******************************************"
done
