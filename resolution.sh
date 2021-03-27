#!/bin/bash -e

[ $# -eq 1 ] || {
    echo "Pass one arg, the path to a video file, and this will output the width and height of" >&2
    echo "stream 0:0 of that file." >&2
    exit 1
}

STREAM=$(ffprobe -i "$1" 2>&1 | grep 'Stream #0:0') || {
    echo "Failed to probe video file to find resolution." >&2
    exit 1
}

if [[ "$STREAM" =~ 1920x1080 ]]; then
    echo "1920 1080"
elif [[ "$STREAM" =~ 720x480 ]]; then
    echo "720 480"
else
    echo "I don't recognize that video size. I'm pretty dumb. Tell me about a new size." >&2
    exit 1
fi
