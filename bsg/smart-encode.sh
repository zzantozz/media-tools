#!/bin/bash -e

# Contains named files representing files already encoded. Remove a file to make it get processed again.
DONEDIR="cache/done"
export DONEDIR
mkdir -p "$DONEDIR"
# Contains the ffmpeg logs to ensure an encode finished successfully
LOGDIR="cache/log"
export LOGDIR
mkdir -p "$LOGDIR"

# Ripping dir holding general ripping tools
RIPPING="/media/plex-media-2/ripping"
export RIPPING

# List of outputs to build the map values from in the function. Can't be an array because those can't be exported.
OUTSTRING="[outa] [outb] [outc] [outd] [oute] [outf] [outg] [outh] [outi] [outj] [outkl] [outm] [outn] [outo] [outp] [outq]"
export OUTSTRING

function debug {
    [ "$DEBUG" = encode ] && echo "$1" >&2
}
export -f debug

function encode_one {
    [ -f "$1" ] || {
	echo "File doesn't exist: '$1'" 2>&1
	exit 1
    }
    set -e
    NEXT="$1"
    BASENAME="$(basename "$NEXT")"
    DIRNAME="$(basename "$(dirname "$NEXT")")"
    CONFIGFILE="data/config/$DIRNAME/$BASENAME"
    debug "Using $CONFIGFILE"
    if [ -f "$CONFIGFILE" ]; then
	source "$CONFIGFILE"
	[ -n "$SEASON" ] || {
	    echo "Config didn't specify a SEASON" >&2
	    exit 1
	}
	[ -n "$EPISODE" ] || {
	    echo "Config didn't specify an EPISODE" >&2
	    exit 1
	}
	S2=$(printf "%0.2d" "$SEASON")
	EPISODE=$(printf "%0.2d" "$EPISODE")
	OUTPUTNAME="Season $SEASON/Battlestar Galactica s${S2}e${EPISODE}"
	[ -n "$DESCRIPTION" ] && OUTPUTNAME="$OUTPUTNAME - $DESCRIPTION"
	OUTPUTNAME="$OUTPUTNAME.mkv"
	DONEFILE="$DONEDIR/$OUTPUTNAME"
    else
	SEASON=$("$RIPPING/season.sh" "$NEXT")
	OUTPUTNAME="Season $SEASON/$BASENAME"
	DONEFILE="$DONEDIR/$BASENAME"
    fi
    DONE=false
    [ -f "$DONEFILE" ] && DONE=true
    [ "$ONE" != "true" ] && [ $DONE = true ] && {
	debug "Done: $DIRNAME/$BASENAME"
	return 0
    }
    echo "Processing $DIRNAME/$BASENAME into $OUTPUTNAME"
    INTERLACED=$(../interlaced.sh -i "$NEXT" -f video)
    [ "$DEBUG" = "encode" ] && echo "Interlacing=$INTERLACED"
    VQ=$("$RIPPING/quality.sh" "$NEXT")
    INPUT="$NEXT"
    [ "$QUALITY" = "rough" ] && {
	OUTPUT="/media/plex-media-2/ripping/bsg-editing/test-encode-$BASENAME"
    } || {
	OUTPUT="/media/plex-media/tv-shows/Battlestar Galactica (2003)/$OUTPUTNAME"
    }
    PROFILE=$(./profile.sh "$NEXT")
    PROFILECONFIGFILE="./data/profiles/$PROFILE"
    [ -f "$PROFILECONFIGFILE" ] && {
	[ "$DEBUG" = "encode" ] && echo "Using profile config $PROFILECONFIGFILE"
	PROFILECONFIG=$(cat "$PROFILECONFIGFILE")
    } || {
	echo "No profile config!"
	exit 1
    }
    source "$PROFILECONFIGFILE"
    FILTER=$(./filter.sh "$NEXT")
    [ "$DEBUG" = "encode" ] && echo "Filter: $FILTER"
    if [ "$INTERLACED" = interlaced ] && [ -n "$FILTER" ]; then
	echo "Interlaced video handling disabled because I'm not sure how to make it work"
	echo "with the -filter_complex. If this comes up, gotta figure out how to add the"
	echo "yadif filter to it. Also stop using the name FILTER. It's used for both the"
	echo "filter_complex value and the yadif filter string. Make the live together."
	exit 1
    fi
    SIMPLEFILTER=unset
    [ $INTERLACED = interlaced ] && SIMPLEFILTER="yadif"
    [ $INTERLACED = progressive ] && SIMPLEFILTER=""
    [ "$SIMPLEFILTER" = "unset" ] && {
    	echo "Invalid interlace value: '$INTERLACED'"
	exit 1
    }
    [ -n "$CUT_STREAMS" ] || {
	echo "CUT_STREAMS should be known by now"
	exit 1
    }
    NMAPS="${#CUT_STREAMS[@]}"
    NMAPS=$((NMAPS-1))
    MAPS=""
    [ -n "$FILTER" ] && {
	ALLOUTS=($OUTSTRING)
	for I in $(seq 0 $NMAPS); do
	    MAPS="$MAPS -map ${ALLOUTS[$I]}"
	done
    } || {
	STREAMS="${CUT_STREAMS[@]}"
	for S in $STREAMS; do
	    MAPS="$MAPS -map $S"
	done
    }
    [ "$DEBUG" = "encode" ] && echo "MAPS: $MAPS"
    # Use locally installed ffmpeg, or a docker container?
    SHOWS="/media/plex-media/tv-shows"
    CMD=(ffmpeg)
    #CMD=(docker run --rm -v "$RIPPING":"$RIPPING" -v "$SHOWS":"$SHOWS" -w "$(pwd)" jrottenberg/ffmpeg -stats)
    CMD+=(-hide_banner -y -i "$NEXT")
    [ -z "$FILTER" ] || CMD+=(-filter_complex "$FILTER")
    [ -z "$SIMPLEFILTER" ] || CMD+=(-filter:0 "$SIMPLEFILTER")
    CMD+=($MAPS)
    CMD+=(-c copy)
    # Do real video encoding, or speed encode for checking the output?
    [ "$QUALITY" = "rough" ] && {
	#CMD+=(-c:0 mpeg2video -threads:0 2)
	CMD+=(-c:0 libx264 -preset ultrafast)
    } || {
	CMD+=(-c:0 libx265 -crf:0 20)
    }
    if [ "$AS_TRANSCODE" = true ] && [ "$AS" = 1 ]; then
	CMD+=(-c:1 ac3 -ac:1 6 -b:1 384k)
	CMD+=(-metadata:s:1 "title=Transcoded Surround for Sonos")
    elif [ "$AS_TRANSCODE" = false ] && [ "$AS" = 1 ]; then
	CMD+=()
    else
	echo "Don't know how to deal with AS_TRANSCODE=$AS_TRANSCODE and AS=$AS" >&2
	exit 1
    fi
    # when there's a second audio stream, it's a stereo commentary stream, but we have to transcode
    # because of the cutting
    CMD+=(-c:2 ac3 -ac:2 2 -b:2 192k)
    CMD+=(-metadata:s:0 "encoded_by=My smart encoder script")
    CMD+=("$OUTPUT")

    for arg in "${CMD[@]}"; do
	echo -n "\"${arg//\"/\\\"}\" "
    done
    echo "&> \"$LOGDIR/$BASENAME.log\""
    date
    "${CMD[@]}" &> "$LOGDIR/$BASENAME.log"
    date
    if "$RIPPING/done.sh" "$NEXT" "$LOGDIR"; then
	mkdir -p "$(dirname "$DONEFILE")"
	debug "All done: touch '$DONEFILE'"
        touch "$DONEFILE"
    else
	echo ""
	echo "Encoding not done?"
	exit 1
    fi
    echo ""
}
export -f encode_one

[ $# -eq 1 ] && ONE=true
[ "$ONE" = true ] && encode_one "$1"
[ -z "$ONE" ] && find /media/plex-media-2/ripping/BSG -name '*.mkv' -print0 | xargs -0I {} bash -c 'encode_one "{}"'
