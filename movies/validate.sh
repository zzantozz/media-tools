#!/bin/bash -e

[ $# -eq 1 ] && [ -f "$1" ] || {
    echo "Pass the path to a movie config to check that all the variables in" >&2
    echo "it are valid." >&2
    exit 1
}

VALIDS=(
    KEEP_STREAMS
    INTERLACED
    OUTPUTNAME
    FFMPEG_EXTRA_OPTIONS
    TRANSCODE_AUDIO
    MOVIENAME
    CROPPING
)

while read -r line; do
    key="${line%=*}"
    [[ "${VALIDS[@]}" =~ $key ]] || {
	echo "Invalid key" >&2
	echo "Key: $key" >&2
	echo "File: $1" >&2
	exit 1
    }
done < "$1"
