#!/bin/bash -e

[ $# -eq 1 ] && [ -f "$1" ] || {
    echo "Pass the path to a movie config to check that all the variables in" >&2
    echo "it are valid." >&2
    exit 1
}

VALIDS=(
    KEEP_STREAMS
    CUT_STREAMS
    INTERLACED
    OUTPUTNAME
    FRAMERATE
    FFMPEG_EXTRA_OPTIONS
    TRANSCODE_AUDIO
    MOVIENAME
    CROPPING
)

while read -r line; do
    key="${line%%=*}"
    [[ "${VALIDS[@]}" =~ $key ]] || [[ "$key" =~ ^# ]] || {
	echo "Invalid key: $key"
	echo "Acceptable keys are:"
	echo -n "  "
	for p in "${VALIDS[@]}"; do
	    echo -n "\"$p\" "
	done
	exit 1
    }
done < "$1"

source "$1"

if [ "$(basename "$1")" = "main" ]; then
    [ -n "$MOVIENAME" ] || {
	echo "Doesn't set a MOVIENAME"
	exit 1
    }
else
    [ -n "$OUTPUTNAME" ] || {
	echo "Doesn't set an OUTPUTNAME"
	exit 1
    }
    [[ "$OUTPUTNAME" =~ \.mkv$ ]] || {
	echo "OUTPUTNAME doesn't end with .mkv"
	exit 1
    }
    MATCH=false
    PLEXDIRS=("Behind The Scenes" "Deleted Scenes" "Featurettes" "Interviews" "Scenes" "Shorts" "Trailers" "Other")
    for p in "${PLEXDIRS[@]}"; do
	[[ "$OUTPUTNAME" =~ ^$p/ ]] && MATCH=true
    done
    [ "$MATCH" = true ] || {
	# If not in a Plex dir, it should be the main movie file, named similarly to the movie directory. With
	# multiple cuts, the movie dir "Blah" could contain "Blah (Theatrical).mkv" and "Blah (Extended).mkv"
	CONFIGDIR="$(dirname "$1")"
	source "$CONFIGDIR/main"
	BASE="${MOVIENAME%%.*}"
	[[ "$OUTPUTNAME" =~ ^"$BASE".*\.mkv$ ]] && MATCH=true
    }
    [ "$MATCH" = true ] || {
	# Also, as a special case, Marvel One-Shots can be moved to the top level. They're included as special
	# features on some discs but recognized as movies in their own right.
        [[ "$OUTPUTNAME" =~ ^Marvel\ One-Shot: ]] && MATCH=true
    }
    [ "$MATCH" = true ] || {
	echo "OUTPUTNAME doesn't match the movie name and doesn't put the output file in a known Plex dir:"
	echo "  $OUTPUTNAME"
	echo "Acceptable dirs are:"
	echo -n "  "
	for p in "${PLEXDIRS[@]}"; do
	    echo -n "\"$p\" "
	done
	exit 1
    }
    STREAMS="${KEEP_STREAMS[@]}"
    [ -n "$STREAMS" ] || {
	echo "Doesn't set KEEP_STREAMS"
	exit 1
    }
    [ "$KEEP_STREAMS" = all ] || [ "${#KEEP_STREAMS[@]}" -gt 1 ] || {
	echo "KEEP_STREAMS should be the string 'all' or an array with more than one thing in it"
	exit 1
    }
    D=[[:digit:]]
    [ -z "$CROPPING" ] || [ "$CROPPING" = none ] || [[ "$CROPPING" =~ ^$D+:$D+:$D+:$D+ ]] || {
	echo "CROPPING should be set to 'none' or a valid cropping value like 1900:800:10:120"
	exit 1
    }
fi
