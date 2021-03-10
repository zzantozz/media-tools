#!/bin/bash

# Used to take one arg, but changed to two to let it adapt to different log file locations

[ $# -eq 2 ] || {
	echo "Checks if an mkv file has been encoded by examining a log file of ffmpeg output."
	echo "Takes two args:"
	echo "1. The name of an mkv file"
	echo "2. The path to a directory containing log files"
	echo ""
	echo 'The log files should be named "$(basename "$1").log" so they can be correlated to'
	echo "the input file."
	exit 1
}

BASENAME=$(basename "$1")
LOGFILE="$2/$BASENAME.log"

[ -f "$LOGFILE" ] || {
	echo "Expected log file doesn't exist for checking doneness:"
	echo "$LOGFILE"
	exit 1
}

# x265 ends with an "encoded ..." line, x264 with a "[libx264 @..." line
tail -1 "$LOGFILE" | grep "^encoded" &>/dev/null || tail -1 "$LOGFILE" | grep '^\[libx264 @.*kb/s:' &>/dev/null && exit 0
exit 1

