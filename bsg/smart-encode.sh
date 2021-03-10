#!/bin/bash -e

# Contains named files representing files already encoded. Remove a file to make it get processed again.
DONEDIR="cache/done"
export DONEDIR
mkdir -p "$DONEDIR"
# Contains the final config used to encode the file of the same name for historical purposes.
CONFIGDIR="cache/config"
export CONFIGDIR
mkdir -p "$CONFIGDIR"
# Contains the ffmpeg logs to ensure an encode finished successfully
LOGDIR="cache/log"
export LOGDIR
mkdir -p "$LOGDIR"

# Ripping dir holding general ripping tools
RIPPING="/media/plex-media-2/ripping"
export RIPPING

export DONES=$(ls "$DONEDIR")

# List of outputs to build the map values from in the function. Can't be an array because those can't be exported.
OUTSTRING="[outa] [outb] [outc] [outd] [oute] [outf] [outg] [outh] [outi] [outj] [outkl] [outm] [outn] [outo] [outp] [outq]"
export OUTSTRING

function encode_one {
	[ -f "$1" ] || {
		echo "File doesn't exist: '$1'" 2>&1
		exit 1
	}
	set -e
	NEXT="$1"
        BASENAME=$(basename "$NEXT")
	DONE=false
        echo "$DONES" | grep "$BASENAME" > /dev/null && DONE=true
	[ "$ONE" != "true" ] && [ $DONE = true ] && {
		[ "$DEBUG" = "encode" ] && echo "$BASENAME is done"
		return 0
	}
	echo "Processing $BASENAME"
	INTERLACED=$(./interlaced.sh "$NEXT")
        [ "$DEBUG" = "encode" ] && echo "Interlacing=$INTERLACED"
	[ $INTERLACED = interlaced ] && {
		echo "Interlaced video handling disabled because I'm not sure how to make it work"
		echo "with the -filter_complex. If this comes up, gotta figure out how to add the"
		echo "yadif filter to it. Also don't use the name FILTER here. It's used later."
		exit 1
	}
	#FILTER=unset
        #[ $INTERLACED = interlaced ] && FILTER="-filter:v:0 yadif"
       	#[ $INTERLACED = progressive ] && FILTER=""
	#[ "$FILTER" = "unset" ] && {
	#	echo "Invalid interlace value: '$INTERLACED'"
	#	exit 1
	#}
        VQ=$("$RIPPING/quality.sh" "$NEXT")
        SEASON=$("$RIPPING/season.sh" "$NEXT")
        INPUT="$NEXT"
	[ "$QUALITY" = "rough" ] && {
		OUTPUT="/media/plex-media-2/ripping/bsg-editing/test-encode-$BASENAME"
	} || {
		OUTPUT="/media/plex-media/tv-shows/Battlestar Galactica (2003)/Season $SEASON/$BASENAME"
	}
	PROFILE=$(./profile.sh "$NEXT")
	PROFILECONFIGFILE="./data/profiles/$PROFILE"
        [ -f "$PROFILECONFIGFILE" ] && {
		[ "$DEBUG" = "encode" ] && echo "Using profile config $PROFILECONFIGFILE"
		PROFILECONFIG=$(cat "$PROFILECONFIGFILE") 
	} || {
		echo "No profile config, skipping"
		return 0
	}
	source "$PROFILECONFIGFILE"
	FILTER=$(./filter.sh "$NEXT")
	[ "$DEBUG" = "encode" ] && echo "Filter: $FILTER"
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
	CMD+=($MAPS)
	# Do real video encoding, or speed encode for checking the output?
	[ "$QUALITY" = "rough" ] && {
		#CMD+=(-c:0 mpeg2video -threads:0 2)
		CMD+=(-c:0 libx264 -preset ultrafast)
	} || {
		CMD+=(-c:0 libx265 -crf:0 20)
	}
	CMD+=(-c:1 ac3 -ac:1 6 -b:1 384k)
	# when there's a second audio stream, it's a stereo commentary stream
	CMD+=(-c:2 ac3 -ac:2 2 -b:2 192k)
	CMD+=(-metadata:s:0 "encoded_by=My smart encoder script")
	CMD+=(-metadata:s:1 "title=Transcoded Surround for Sonos")
	CMD+=("$OUTPUT")

	for arg in "${CMD[@]}"; do
		echo -n "\"${arg//\"/\\\"}\" "
	done
	echo "&> \"$LOGDIR/$BASENAME.log\""
	date
	"${CMD[@]}" &> "$LOGDIR/$BASENAME.log"
	date
	"$RIPPING/done.sh" "$NEXT" "$LOGDIR" && touch "$DONEDIR/$BASENAME" || {
		echo ""
		echo "Encoding not done?"
		exit 1
	}
	echo ""
}
export -f encode_one

[ $# -eq 1 ] && ONE=true
[ "$ONE" = true ] && encode_one "$1"
[ -z "$ONE" ] && find /media/plex-media-2/ripping/BSG -name '*.mkv' -print0 | xargs -0I {} bash -c 'encode_one "{}"'
