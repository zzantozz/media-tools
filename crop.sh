#!/bin/bash -e

[ -f "$1" ] || {
    echo "Enter path to a video file to determine the crop dimensions" >&2
    exit 1
}

CROPDETECT=$(ffmpeg -y -ss 600 -i "$1" -t 10 -filter:v cropdetect -f null - 2>&1 | grep '^\[Parsed_cropdetect' | awk '/crop/ {print $NF}' | sort | uniq -c)
if [ $(echo "$CROPDETECT" | wc -l) = 1 ]; then
    VALUE=$(echo $CROPDETECT | cut -d ' ' -f 2)
    [ "$DEBUG" = crop ] && echo "Unanimous cropdetect: $VALUE" >&2
    echo $VALUE
    exit 0
fi

echo "Cropdetect wasn't unanimous. Try looking for majority or something." >&2
[ "$DEBUG" = crop ] && echo "$CROPDETECT" >&2
exit 1
