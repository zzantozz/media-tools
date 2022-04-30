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

# List of outputs to build the map values from in the function. Can't be an array because those can't be exported.
OUTSTRING="[outa] [outb] [outc] [outd] [oute] [outf] [outg] [outh] [outi] [outj] [outkl] [outm] [outn] [outo] [outp] [outq]"
export OUTSTRING

# If DRYRUN is set, export it so the function sees it
[ -n "$DRYRUN" ] && export DRYRUN

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
    # For now, processing any movie file requires a config because only manual
    # inspection can tell which streams to keep. Loading the config early also
    # gives a place to eagerly set things that could be discovered later but
    # may fail, like the interlace value.
    CONFIGFILE="$CONFIGDIR/$PARTIALNAME"
    if [ -f "$CONFIGFILE" ]; then
	CONFIGDIR="$(dirname "$CONFIGFILE")"
	MAINFILE="$CONFIGDIR/main"
	if [ -f "$MAINFILE" ]; then
	    debug "Loading main movie config: $MAINFILE"
	    source "$MAINFILE" || {
		echo "Failed to source $MAINFILE" >&2
		exit 1
	    }
	fi
	debug "Using config: $CONFIGFILE"
	source "$CONFIGFILE" || {
	    echo "Failed to source $CONFIGFILE" >&2
	    exit 1
	}
    else
	echo "Missing config file: $CONFIGFILE" >&2
	exit 1
    fi

    # Figure out what our output file is
    [ -n "$OUTPUTNAME" ] || {
	echo "No OUTPUTNAME set in config." >&2
	exit 1
    }
    [ -z "$MOVIENAME" ] && MOVIENAME="$(dirname "$PARTIALNAME")"
    PARTIALOUTPUT="$MOVIENAME/$OUTPUTNAME"
    [ "$QUALITY" = "rough" ] && {
	OUTPUT="$TOOLSDIR/test-encode-$(basename "$PARTIALOUTPUT")"
    } || {
	[ -n "$OUTPUTNAME" ] || {
	    echo "OUTPUTNAME not set in config: $CONFIGFILE" >&2
	    exit 1
	}
	# Let movie name be set in config
	OUTPUT="$MOVIESDIR/$PARTIALOUTPUT"
    }

    DONEFILE="$DONEDIR/$PARTIALOUTPUT"
    DONE=false
    debug "Check if already done; done file: $DONEFILE"
    [ -f "$DONEFILE" ] && DONE=true
    [ ! -f "$OUTPUT" ] && DONE=false
    [ "$ONE" != "true" ] && [ $DONE = true ] && {
	echo "Done: $PARTIALNAME -> $PARTIALOUTPUT" >&2
	return 0
    }
    echo "Processing $PARTIALNAME into $PARTIALOUTPUT" >&2
    DUR=$(ffprobe -v error -select_streams v:0 -show_entries stream_tags=DURATION-eng -of default=noprint_wrappers=1:nokey=1 "$FULLPATH" | cut -d '.' -f 1)
    echo "Duration: $DUR"

    # Let some values be set in config. Otherwise, figure them out.
    [ -n "$INTERLACED" ] && CONFIG_INTERLACED="$INTERLACED"
    [ -n "$CROPPING" ] && CONFIG_CROPPING="$CROPPING"

    if [ -z "$CONFIG_INTERLACED" ] || [ -z "$CONFIG_CROPPING" ]; then
	echo "Analyzing..."
	echo " - $(date)"
	ANALYSIS=$("$TOOLSDIR/analyze.sh" "$FULLPATH")
	echo " - $(date)"
	eval "$ANALYSIS"
    fi

    [ -n "$CONFIG_INTERLACED" ] && [ -n "$INTERLACED" ] && [ "$CONFIG_INTERLACED" != "$INTERLACED" ] && {
	echo "Config interlace value doesn't match detected interlace value." >&2
	echo "Config  : $CONFIG_INTERLACED" >&2
	echo "Detected: $INTERLACED" >&2
	echo "Using configured value" >&2
    }
    INTERLACED="${CONFIG_INTERLACED:-$INTERLACED}"
    [ -n "$CONFIG_CROPPING" ] && [ -n "$CROPPING" ] && [ "$CONFIG_CROPPING" != "$CROPPING" ] && {
	echo "Config cropping value doesn't match detected cropping value." >&2
	echo "Config  : $CONFIG_CROPPING" >&2
	echo "Detected: $CROPPING" >&2
	# I want to abort here, but I found a movie where this is actually needed. Guns of Navarone detects a crop of 710:358:4:60, but
	# makes the video all crazy stretched out. 710:360:4:60 works fine.
	#exit 1
    }
    CROPPING="${CONFIG_CROPPING:-$CROPPING}"
    debug "Interlacing: $INTERLACED"
    [ "$INTERLACED" = progressive ] || [ "$INTERLACED" = interlaced ] || {
    	echo "Invalid interlace value: '$INTERLACED'" >&2
    	exit 1
    }
    debug "Cropping: $CROPPING"
    [ -z "$CROPPING" ] && {
	echo "No cropping determined. There should always be a value here." >&2
	exit 1
    }

    VQ=$("$TOOLSDIR/quality.sh" "$FULLPATH")
    debug "Quality: $VQ"

    if [ -f "data/cuts/$PARTIALNAME" ]; then
	FILTERCMD=("./filter.sh" "$FULLPATH")
	EXTRAS=()
	[ "$INTERLACED" = "interlaced" ] && EXTRAS+=("yadif")
	[ "$CROPPING" = none ] || EXTRAS+=("crop=$CROPPING")
	[ -n "$EXTRAS" ] && FILTERCMD+=(-v "$(IFS=,; printf "%s" "${EXTRAS[*]}")")
	COMPLEXFILTER=$("${FILTERCMD[@]}") || {
	    echo "filter.sh failed to determine complex filter string" >&2
	    exit 1
	}
	debug "complex_filter: $COMPLEXFILTER"
    else
        VFILTERS=()
        [ "$INTERLACED" = interlaced ] && VFILTERS+=("yadif")
        [ "$CROPPING" = none ] || VFILTERS+=("crop=$CROPPING")
    fi
    [ -n "$KEEP_STREAMS" ] || {
	echo "KEEP_STREAMS should be known by now" >&2
	exit 1
    }
    MAPS=""
    if [ -n "$COMPLEXFILTER" ]; then
	debug "have complex filter; mapping this way"
	NMAPS="${#CUT_STREAMS[@]}"
	NMAPS=$((NMAPS-1))
	ALLOUTS=($OUTSTRING)
	for I in $(seq 0 $NMAPS); do
	    MAPS="$MAPS -map ${ALLOUTS[$I]}"
	done
    else
	debug "no complex filter; mapping that way"
	STREAMS="${KEEP_STREAMS[@]}"
	for S in $STREAMS; do
	    MAPS="$MAPS -map $S"
	done
    fi
    [ -n "$TRANSCODE_AUDIO" ] && {
	MAPS="${MAPS# -map 0:0}"
	MAPS="-map 0:0 -map $TRANSCODE_AUDIO $MAPS"
    }
    debug "MAPS: $MAPS"
    VFILTERSTRING="${VFILTERS[0]}"
    i=1
    while [ $i -lt "${#VFILTERS[@]}" ]; do
	VFILTERSTRING="$VFILTERSTRING,${VFILTERS[$i]}"
	i=$((i+1))
    done

    if [ -n "$COMPLEXFILTER" ] && [ -n "$VFILTERSTRING" ]; then
	echo "I came up with both a complex filter and a simple filter string." >&2
	echo "This is an error because you can't use both filter_complex and" >&2
	echo "-filter:v in ffmpeg. See how we got here." >&2
	echo "Simple filter string : $VFILTERSTRING" >&2
	echo "Complex filter string: $COMPLEXFILTER" >&2
	exit 1
    fi

    # Use locally installed ffmpeg, or a docker container?
    CMD=(ffmpeg)
    #CMD=(docker run --rm -v "$TOOLSDIR":"$TOOLSDIR" -v "$MOVIESDIR":"$MOVIESDIR" -w "$(pwd)" jrottenberg/ffmpeg -stats)

    CMD+=(-hide_banner -y -i "$FULLPATH")

    # This because several videos end up failing with the "Too many packets buffered for output stream XXX" error.
    # I don't think this will cause any problems.
    CMD+=(-max_muxing_queue_size 1024)

    # Use one filter or the other, if set. Setting both will cause an error, but that's checked earlier, and even if it's not,
    # ffmpeg will tell you what you did wrong.
    [ -z "$COMPLEXFILTER" ] || CMD+=(-filter_complex "$COMPLEXFILTER")
    CMD+=($MAPS -c copy)
    [ -n "$VFILTERSTRING" ] && CMD+=("-filter:v:0" "$VFILTERSTRING")

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

    # If cutting is happening, stream 1 should be the best audio for the purpose and has to be transcoded
    # due to the cutting.
    [ -n "$COMPLEXFILTER" ] && {
	CMD+=(-c:1 ac3 -ac:1 6 -b:1 384k)
    }

    CMD+=(-metadata:s:0 "encoded_by=My smart encoder script")
    [ "$QUALITY" != "rough" ] && [ -n "$TRANSCODE_AUDIO" ] && {
	CMD+=(-metadata:s:1 "title=Transcoded Surround for Sonos")
    }
    CMD+=($FFMPEG_EXTRA_OPTIONS)
    CMD+=("$OUTPUT")
    LOGFILE="$LOGDIR/$MOVIENAME/$OUTPUTNAME.log"
    DONEFILE="$DONEDIR/$MOVIENAME/$OUTPUTNAME"

    for arg in "${CMD[@]}"; do
	echo -n "\"${arg//\"/\\\"}\" "
    done
    echo "&> \"$LOGFILE\""
    echo ""
    echo "View logs:"
    echo "tail -f \"$LOGFILE\""
    echo "tail -F currentlog"
    echo ""
    echo " - $(date)"
    mkdir -p "$(dirname "$OUTPUT")"
    mkdir -p "$(dirname "$LOGFILE")"
    mkdir -p "$(dirname "$DONEFILE")"
    if [ -n "$DRYRUN" ]; then
	echo "  -- dry run requested, not running"
    else
	ln -fs "$LOGFILE" currentlog
	"${CMD[@]}" &> "$LOGFILE"
    fi
    echo " - $(date)"

    if [ "$QUALITY" = "rough" ]; then
        echo "Rough encode done, not marking file as done done."
    elif [ -n "$DRYRUN" ]; then
        echo "Dry run, not marking file as done done."
    elif "$TOOLSDIR/done.sh" "$PARTIALOUTPUT" "$LOGDIR"; then
        echo "Marking file as done done."
        mkdir -p "$(dirname "$DONEFILE")"
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
[ -z "$ONE" ] && find "$INPUTDIR" -name '*.mkv' -mmin +2 -print0 | sort -z | xargs -0I {} bash -c 'encode_one "{}"'
