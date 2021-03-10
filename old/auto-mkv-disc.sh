#!/bin/bash

set -e

# Several lines copied from other makemkv shell script
echo "WARNING   This is a weird blend of bash and windows stuff since MakeMKV is only"
echo "WARNING   installed in windows now. The logic is bash, but some of the commands"
echo "WARNING   and paths have to be windows."
echo ""

if [ -z "$DISC" ]; then
    echo "Set env var DISC to override default output directory."
    echo ""
fi

MAKEMKV_BINARY="/mnt/c/Program\ Files\ \(x86\)/MakeMKV/makemkvcon.exe"
[ -z "$BASE_OUTPUT_DIR" ] && BASE_OUTPUT_DIR="/mnt/d/ripping"

[ -n "$DISC" ] && TARGET_DIR="$DISC"
[ -n "$DISK" ] && TARGET_DIR="$DISK"
[ -z "$TARGET_DIR" ] && TARGET_DIR="__mkv_from_disc_without_info_lookup"
FINAL_TARGET_DIR="$BASE_OUTPUT_DIR\\$TARGET_DIR"

mkdir "$FINAL_TARGET_DIR"
touch "$FINAL_TARGET_DIR/.lock"
touch "$FINAL_TARGET_DIR/.ripping"
CMD="$MAKEMKV_BINARY mkv disc:0 all $FINAL_TARGET_DIR"
echo "Executing: $CMD"
echo "**************************************"
$CMD
echo "**************************************"
rm "$FINAL_TARGET_DIR/.ripping"
rm "$FINAL_TARGET_DIR/.lock"
touch "$FINAL_TARGET_DIR/.ripping-finished"
