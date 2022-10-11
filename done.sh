#!/bin/bash

# Used to take one arg, but changed to two to let it adapt to different log file locations

[ $# -eq 2 ] || {
	echo "Checks if an mkv file has been encoded by examining a log file of ffmpeg output."
	echo "Takes two args:"
	echo "1. The name or relative path of an mkv file"
	echo "2. The path to a directory containing log files"
	echo ""
	echo 'Returns 0 if a log file named "$1.log" or "$(basename "$1").log" exists and looks'
	echo 'looks like a finished ffmpeg encode. Returns 1 otherwise.'
	exit 1
}

BASENAME=$(basename "$1")
LOGFILE1="$2/$BASENAME.log"
LOGFILE2="$2/$1.log"

[ -f "$LOGFILE1" ] && FILE="$LOGFILE1"
[ -f "$LOGFILE2" ] && FILE="$LOGFILE2"
[ -n "$FILE" ] || {
	echo "Couldn't find log file to check doneness. Expected one of:" >&2
	echo "- $LOGFILE1" >&2
	echo "- $LOGFILE2" >&2
	exit 1
}

# x265 ends with an "encoded ..." line, x264 with a "[libx264 @..." line
tail -1 "$FILE" | grep "^encoded" &>/dev/null || tail -1 "$FILE" | grep '^\[libx264 @.*kb/s:' &>/dev/null && exit 0
exit 1

