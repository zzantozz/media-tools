#!/bin/bash -e

# Contains named files representing files already encoded. Remove a file to make it get processed again.
DONEDIR="cache/done"
export DONEDIR
mkdir -p "$DONEDIR"
# Contains the ffmpeg logs to ensure an encode finished successfully
LOGDIR="cache/log"
export LOGDIR
mkdir -p "$LOGDIR"
# Contains config files with data for each movie file to be encoded.
CONFIGDIR="data/config"
export CONFIGDIR
# Directory to scan for raw mkv's ripped from disc
INPUTDIR="/media/plex-media-2/ripping/movies-in"
export INPUTDIR
# Root directory of movies library, where final transcoded movies go, possibly in a subdirectory to organize
# related items the way Plex likes them.
MOVIESDIR="/media/plex-media/movies"
export MOVIESDIR
# Directory holding general ripping tools
TOOLSDIR="/media/plex-media-2/ripping/tools"
export TOOLSDIR

export DONES=$(find "$DONEDIR" -type f)

# List of outputs to build the map values from in the function. Can't be an array because those can't be exported.
OUTSTRING="[outa] [outb] [outc] [outd] [oute] [outf] [outg] [outh] [outi] [outj] [outkl] [outm] [outn] [outo] [outp] [outq]"
export OUTSTRING

function debug {
    [ "$DEBUG" = "encode" ] && echo -e "$1" 1>&2
    return 0
}
export -f debug

function encode_one {
    [ -f "$1" ] || {
	echo "File doesn't exist: '$1'" 2>&1
	exit 1
    }
    set -e
    # Absolute path to the movie file
    FULLPATH="$1"
    # The unique name for this movie, consisting of the parent dir and file name
    PARTIALNAME="${1#$INPUTDIR/}"
    DONE=false
    echo "$DONES" | grep "$PARTIALNAME" > /dev/null && DONE=true
    [ "$ONE" != "true" ] && [ $DONE = true ] && {
	debug "$PARTIALNAME is done"
	return 0
    }
    echo "Processing $PARTIALNAME"
    # For now, processing any movie file requires a config because only manual
    # inspection can tell which streams to keep. Loading the config early also
    # gives a place to eagerly set things that could be discovered later but
    # may fail, like the interlace value.
    CONFIGFILE="$CONFIGDIR/$PARTIALNAME"
    if [ -f "$CONFIGFILE" ]; then
	debug "Using config: $CONFIGFILE"
	source "$CONFIGFILE"
    else
	echo "Missing config file: $CONFIGFILE" >&2
	exit 1
    fi
    # Let interlace value be set in config. Otherwise, figure it out.
    [ -z "$INTERLACED" ] && INTERLACED=$("$TOOLSDIR/interlaced.sh" "$FULLPATH")
    debug "Interlacing: $INTERLACED"
    VFILTER=unset
    [ $INTERLACED = interlaced ] && VFILTER="-filter:v:0 yadif"
    [ $INTERLACED = progressive ] && VFILTER=""
    [ "$VFILTER" = "unset" ] && {
    	echo "Invalid interlace value: '$INTERLACED'" >&2
    	exit 1
    }
    debug "vfilter: '$VFILTER'"
    VQ=$("$TOOLSDIR/quality.sh" "$FULLPATH")
    debug "Quality: $VQ"
    [ "$QUALITY" = "rough" ] && {
	OUTPUT="$TOOLSDIR/test-encode-$(basename $FULLPATH)"
    } || {
	[ -n "$OUTPUTNAME" ] || {
	    echo "OUTPUTNAME not set in config: $CONFIGFILE" >&2
	    exit 1
	}
	OUTPUT="$MOVIESDIR/$(dirname "$PARTIALNAME")/$OUTPUTNAME"
    }
    if [ -f "data/cuts/$PARTIALNAME" ]; then
	echo "Video cutting with complex_filter not yet implemented here" >&2
	COMPLEXFILTER=$("$TOOLSDIR/filter.sh" "$NEXT")
	debug "complex_filter: $COMPLEXFILTER"
	exit 1
    else
	COMPLEXFILTER=""
    fi
    [ -n "$VFILTER" ] && [ -n "$COMPLEXFILTER" ] && {
	echo "Video is interlaced (needs yadif filter) and also has a" >&2
	echo "complex_filter generated for it. If this comes up, gotta" >&2
	echo "figure out how to apply both filters at the same time." >&2
	exit 1
    }
    [ -n "$KEEP_STREAMS" ] || {
	echo "KEEP_STREAMS should be known by now"
	exit 1
    }
    MAPS=""
    [ -n "$COMPLEXFILTER" ] && {
	NMAPS="${#KEEP_STREAMS[@]}"
	NMAPS=$((NMAPS-1))
	ALLOUTS=($OUTSTRING)
	for I in $(seq 0 $NMAPS); do
	    MAPS="$MAPS -map ${ALLOUTS[$I]}"
	done
    } || {
	STREAMS="${KEEP_STREAMS[@]}"
	for S in $STREAMS; do
	    MAPS="$MAPS -map $S"
	done
    }
    [ -n "$TRANSCODE_AUDIO" ] && {
	TAILMAPS="${MAPS# -map 0:0}"
	MAPS="-map 0:0 -map $TRANSCODE_AUDIO $TAILMAPS"
    }
    debug "MAPS: $MAPS"
    # Use locally installed ffmpeg, or a docker container?
    CMD=(ffmpeg)
    #CMD=(docker run --rm -v "$TOOLSDIR":"$TOOLSDIR" -v "$MOVIESDIR":"$MOVIESDIR" -w "$(pwd)" jrottenberg/ffmpeg -stats)
    CMD+=(-hide_banner -y -i "$FULLPATH")
    [ -z "$COMPLEXFILTER" ] || CMD+=(-filter_complex "$COMPLEXFILTER")
    CMD+=($MAPS -c copy)
    [ -z "$VFILTER" ] || CMD+=($VFILTER)
    # Do real video encoding, or speed encode for checking the output?
    [ "$QUALITY" = "rough" ] && {
	#CMD+=(-c:0 mpeg2video -threads:0 2)
	CMD+=(-c:0 libx264 -preset ultrafast)
    } || {
	CMD+=(-c:0 libx265 -crf:0 "$VQ")
    }
    [ "$QUALITY" != "rough" ] && [ -n "$TRANSCODE_AUDIO" ] && {
	CMD+=(-c:1 ac3 -ac:1 6 -b:1 384k)
    }
    CMD+=(-metadata:s:0 "encoded_by=My smart encoder script")
    [ "$QUALITY" != "rough" ] && [ -n "$TRANSCODE_AUDIO" ] && {
	CMD+=(-metadata:s:1 "title=Transcoded Surround for Sonos")
    }
    CMD+=($FFMPEG_EXTRA_OPTIONS)
    CMD+=("$OUTPUT")
    LOGFILE="$LOGDIR/$PARTIALNAME.log"
    DONEFILE="$DONEDIR/$PARTIALNAME"

    for arg in "${CMD[@]}"; do
	echo -n "\"${arg//\"/\\\"}\" "
    done
    echo "&> \"$LOGFILE\""
    date
    mkdir -p "$(dirname "$OUTPUT")"
    mkdir -p "$(dirname "$LOGFILE")"
    mkdir -p "$(dirname "$DONEFILE")"
    "${CMD[@]}" &> "$LOGFILE"
    date
    "$TOOLSDIR/done.sh" "$PARTIALNAME" "$LOGDIR" && touch "$DONEDIR/$PARTIALNAME" || {
	    echo ""
	    echo "Encoding not done?"
	    exit 1
	}
    echo ""
}
export -f encode_one

[ $# -eq 1 ] && ONE=true
[ "$ONE" = true ] && encode_one "$1"
[ -z "$ONE" ] && find "$INPUTDIR" -name '*.mkv' -print0 | xargs -0I {} bash -c 'encode_one "{}"'
