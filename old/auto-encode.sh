#!/bin/bash

# The intent of this script is to run on a cron in a headless linux server with a good handbrake cli
# build on it. It's the second stage of my media pipeline, the first of which is the script that
# provides an autoplay handler to rip discs upon insertion. Hidden trigger files play an important
# role in the orchestration of the process. Stages can only begin if appropriate trigger files
# are/aren't  in place.

set -e

# WARNING  This is a real bash script that must be run inside a linux VM
# WARNING  that has handbrake-cli and appropriate encoders installed.

[ -z "$ROOT_DIR" ] && ROOT_DIR="/mnt/ripping-x"
[ -z "$SOURCE_DIR" ] && SOURCE_DIR="$ROOT_DIR/__1-auto-ripped"
[ -z "$DEST_DIR" ] && DEST_DIR="$ROOT_DIR/__2-auto-encoded"
[ -z "$HANDBRAKE_BIN" ] && HANDBRAKE_BIN="/usr/local/bin/HandBrakeCLI"
GLOBAL_LOCK="$SOURCE_DIR/.encoding"
GENERIC_LOCK_NAME=".lock"
TRIGGER_FILE_NAME=".ripping-finished"
PROCESSED_FILE_NAME=".encoding-finished"
[ -z "$QUALITY" ] && QUALITY=20
[ -z "$CLEAN_SOURCE" ] && CLEAN_SOURCE=false

# For logging...
echo ""
date
echo "Checking $SOURCE_DIR for things to process"

# Since this script is meant to be scheduled, we need a lock file to ensure it doesn't run
# multiple times simultaneously.
if [ -f "$GLOBAL_LOCK" ]; then
    echo "vvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvv"
    echo "Bailing out completely due to presence of global lock file: $GLOBAL_LOCK"
    echo "^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^"
    exit 1
fi
touch "$GLOBAL_LOCK"

# Account for spaces in file names by setting 'for loops separator' with IFS
IFS=$(echo -en "\n\b")

for MOVIE_NAME in `ls -1 $SOURCE_DIR`; do
  ONE_RIP_DIR="$SOURCE_DIR/$MOVIE_NAME"
  LOCK="$ONE_RIP_DIR/$GENERIC_LOCK_NAME"
  TRIGGER="$ONE_RIP_DIR/$TRIGGER_FILE_NAME"
  PROCESSED="$ONE_RIP_DIR/$PROCESSED_FILE_NAME"
  echo ""
  echo " --> $MOVIE_NAME"
  if [ -f "$LOCK" ]; then
    echo "vvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvv"
    echo "Skipping due to lock file: $LOCK"
    echo "^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^"
    continue
  fi
  if [ ! -f "$TRIGGER" ]; then
    echo "vvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvv"
    echo "Skipping due to missing trigger: $TRIGGER"
    echo "^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^"
    continue
  fi
  if [ -f "$PROCESSED" ]; then
    echo "vvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvv"
    echo "Skipping because it's marked processed by: $PROCESSED"
    echo "^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^"
    continue
  fi
  touch $LOCK
  touch "$ONE_RIP_DIR/.encoding"
  for TITLE in `ls -1 "$ONE_RIP_DIR" | grep '.mkv$'`; do
    BASE_NAME="${TITLE%.*}"
    BASE_OUTPUT_NAME="${MOVIE_NAME}__${BASE_NAME}"
    LOG_FILE="$ONE_RIP_DIR/$BASE_OUTPUT_NAME-encode.log"
    START_SIZE=`stat -c %s "$ONE_RIP_DIR/$TITLE"`
    echo "vvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvv"
    echo " Encode     :"
    echo " Start      : $(date)"
    echo " Source     : $ONE_RIP_DIR/$TITLE"
    echo " Dest       : $DEST_DIR/$BASE_OUTPUT_NAME.mkv"
    echo " Log        : $LOG_FILE"
    echo " Start size : $START_SIZE ($((START_SIZE/1024/1024)) MB)"
    echo "----------------------------------------------------------------------------------------------------"
    ENCODE_SUCCESS=false
    # Grab stream data before and after so I can figure out what's going on with forced subtitles.
    [ -n "$PROBE_STREAMS" ] && ffprobe -show_streams "$ONE_RIP_DIR/$TITLE" > "$ONE_RIP_DIR/$BASE_OUTPUT_NAME.streams-before.txt" 2> /dev/null

    # Notes:
    # - write to mkv because multiple audio and subtitle tracks
    # - decomb bob seems the best for any input destined for non-interlaced output
    # - quality 20 seems good for dvd or blu-ray destined for 1080p output; reportedly,
    #   you can get away with quality 22 for bluray
    # - the --*-lang-list options paired with the --all-* makes sure I get all english
    #   audio and subtitle tracks
    $HANDBRAKE_BIN \
      --input "$ONE_RIP_DIR/$TITLE" \
      --output "$DEST_DIR/$BASE_OUTPUT_NAME.mkv" \
      --encoder x264 \
      --decomb bob \
      --quality $QUALITY \
      --aencoder copy \
      --audio-lang-list eng \
      --all-audio \
      --subtitle-lang-list eng \
      --subtitle scan \
      --all-subtitles &>"$LOG_FILE" && ENCODE_SUCCESS=true

    [ -n "$PROBE_STREAMS" ] && ffprobe -show_streams "$DEST_DIR/$BASE_OUTPUT_NAME.mkv" > "$ONE_RIP_DIR/$BASE_OUTPUT_NAME.streams-after.txt" 2> /dev/null
    #echo "vvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvv"
    [ $ENCODE_SUCCESS = true ] && {
      END_SIZE=`stat -c %s $DEST_DIR/$BASE_OUTPUT_NAME.mkv`
      echo " End size   : $END_SIZE ($((END_SIZE/1024/1024)) MB)"
      echo " Space saved: $((START_SIZE-END_SIZE)) ($(((START_SIZE-END_SIZE)/1024/1024)) MB)"
      [ $ENCODE_SUCCESS = true -a $CLEAN_SOURCE = true ] && {
        # Free up space.
        echo " Removing source file because CLEAN_SOURCE = $CLEAN_SOURCE"
        rm -f "$ONE_RIP_DIR/$TITLE"
      }
      echo " Completed $ONE_RIP_DIR/$TITLE"
    }
    [ $ENCODE_SUCCESS = false ] && {
      echo " Failed to encode $ONE_RIP_DIR/$TITLE"
    }
    echo "^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^"
  done
  rm "$ONE_RIP_DIR/.encoding"
  rm $LOCK
  touch $PROCESSED
done

rm "$GLOBAL_LOCK"
