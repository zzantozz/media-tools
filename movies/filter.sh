#!/bin/bash -e

function debug {
	[ "$DEBUG" = "filter" ] && echo -e "$1" 1>&2
	return 0
}

[ "$#" -gt 0 ] && [ -f "$1" ] || {
	debug "Pass the name of an episode to generate a filter string for ffmpeg's complex_filter."
	debug "Prints the filter string to use. The number of outputs that need to be mapped will be"
	debug "the number of items in the CUT_STREAMS array in the profile that matches the input file."
	debug "The output names will be [outa], [outb], etc."
	exit 1
}

# Most things use 23.98, but at least one (Ghostbusters) is 59.92, so let this be overridden
[ -n "$FRAMERATE" ] || FRAMERATE=23.98
FILE="$1"
shift
while getopts "v:" opt; do
    case $opt in
	v)
	    EXTRA_VFILTERS=$OPTARG
	    ;;
	*)
	    echo "Invalid option to $0" >&2
	    exit 1
	    ;;
    esac
done
debug "Using extra video filters from command line: $EXTRA_VFILTERS"
BASENAME="$(basename "$FILE")"
MOVIEDIR="$(basename $(dirname "$FILE"))"
CUTS_FILE="data/cuts/$MOVIEDIR/$BASENAME"

[ -f "$CUTS_FILE" ] || {
	debug "Not filtering because cuts file missing: $CUTS_FILE"
	echo ""
	exit 0
}

readarray -t TIMESTAMPS < "$CUTS_FILE"
#TIMESTAMPS=()
#while IFS="" read -r p || [ -n "$p" ]
#do
#	echo "read '$p'"
#	[ -n "$p" ] && TIMESTAMPS+=($p)
#done < "$CUTS_FILE"

# Detect format. Format 1 is the way I started doing it, with one timestamp per line. Timestamps
# were to the millisecond. Each pair of timestamps indicated a section of video to keep, so the
# first was always 00:00:00.000. Each subsequent line and timestamp indicated a stop and start,
# alternating. The end time was omitted, implying everything the final timestamp to the end is
# always kept.
#
# Format 2 is more flexible. Each line contains two timestamps with seconds and frames like
# hh:mm:ssFf[f]. The F is literal, and the number of frames can be one or two digits. Each pair
# of timestamps in this format is a section to cut out, so an empty file implies cut nothing.
# Additional parameters following timestamp pairs allow for fading options, like:
# fadein=0.5
# fadeout=1.0
# A fadeout applies to the start of the cut, and a fadein applies to the end of it.
FORMAT=unknown
[[ "${TIMESTAMPS[0]}" =~ [[:digit:]]{2}:[[:digit:]]{2}:[[:digit:]]{2}.[[:digit:]]{3} ]] && FORMAT=1
[[ "${TIMESTAMPS[0]}" =~ [[:digit:]]{2}:[[:digit:]]{2}:[[:digit:]]{2}F[[:digit:]]{1,2} ]] && FORMAT=2
debug "Cuts file format: $FORMAT"

[ "$FORMAT" = "unknown" ] && {
	debug "Didn't detect timestamp format"
	exit 1
}
[ $FORMAT -eq 1 ] && [ $(("${#TIMESTAMPS[@]}" % 2)) -eq 0 ] && {
        debug "Bad cuts file: '$CUTS_FILE'"
	debug "For format 1 (old style) there should be an odd number of timestamps because it should"
        debug "be a number of start/end pairs plus a final timestamp to resume to the end of the video."
        exit 1
}

debug "Cuts to make:\n${TIMESTAMPS[@]}"

CONFIGFILE="data/config/$MOVIEDIR/$BASENAME"
debug "Using config file $CONFIGFILE"

source "$CONFIGFILE"
[ -n "$CUT_STREAMS" ] || {
	debug "No CUT_STREAMS in config file $CONFIGFILE"
	debug "You need to configure which streams to cut for the filtering."
	exit 1
}
debug "Streams to cut: ${CUT_STREAMS[@]}"

# Converts hh:mm:ss.SSS to decimal seconds
function ts_to_s {
	[ $FORMAT -eq 1 ] || {
		debug "This function only deals with format 1"
		exit 1
	}
	[[ "$1" =~ [[:digit:]]{2}:[[:digit:]]{2}:[[:digit:]]{2}.[[:digit:]]{3} ]] || {
               	debug "Malformed input timestamp: $1"
		debug "Should be hh:mm:ss.SSS"
		exit 1
	}
        IFS=":.F" read -r h m s ms <<<"$1"
	# Ensure decimal notation in case of parts like "09", which would be treated as octal
	h="10#$h"
	m="10#$m"
	s="10#$s"
	SECS=$((h*3600 + m*60 + s))
        printf "%d.%d" $SECS $ms
}

# Adds/subtracts frames to a format 2 timestamps and outputs the results as SECONDS.MILLIS like ffmpeg wants
function add_frames {
	IFS=":F" read -r h m s f <<<"$1"
	# Ensure decimal notation in case of parts like "09", which would be treated as octal
	h="10#$h"
	m="10#$m"
	s="10#$s"
	f="10#$f"
	FULL_SECS=$((h*3600 + m*60 + s))
	debug "h=$h m=$m s=$s f=$f FULL_SECS=$FULLSECS arg2=$2"
	f=$((f + $2))
	HIGHESTFRAME=$(printf "%.0f" "$FRAMERATE")
	debug " ***** highest frame = $HIGHESTFRAME (rate = $FRAMERATE)"
	[ $f -lt 0 ] && {
		f=$HIGHESTFRAME
		FULL_SECS=$((FULL_SECS-1))
	}
	[ $f -gt $HIGHESTFRAME ] && {
	    debug " **** $f > $HIGHESTFRAME, rolling over"
		f=0
		FULL_SECS=$((FULL_SECS+1))
	}
	TIME=$(echo "$FULL_SECS + $f/$FRAMERATE" | bc -l)
	debug "$1 + $2 = $FULL_SECS secs + $f frames = TIME=$TIME"
	printf "%0.3f" $TIME
}

# Stores the segments of the video to keep. Each array item is a string like "start_secs stop_secs".
SEGMENTS=()
# In format 2, additional modifiers can follow the timestamps to allow for fading, like
# 00:01:02F3 01:02:03F4 fadeout=1.0 fadein=0.5
# Modifiers will be stored here, corresponding to segments by index
MODIFIERS=()

[ $FORMAT -eq 1 ] && {
	# Convert cut timestamps to seconds and populate SEGMENTS
	I=0
	MAX=$(("${#TIMESTAMPS[@]}" - 1))
	while [ $I -lt $MAX ]; do
	        START="${TIMESTAMPS[I]}"
	        I=$((I+1))
	        END="${TIMESTAMPS[I]}"
	        I=$((I+1))
	        START_S=$(ts_to_s $START)
	        END_S=$(ts_to_s $END)
	        SEGMENT="$START_S $END_S"
	        SEGMENTS+=("$SEGMENT")
	done
	# A final segment containing the magic value "end"
	LAST_TS=$(ts_to_s "${TIMESTAMPS[-1]}")
	SEGMENTS+=("$LAST_TS end")
}
[ $FORMAT -eq 2 ] && {
	LAST="0"
	I=0
        MAX=$(("${#TIMESTAMPS[@]}"))
	MODNEXT=""
        while [ $I -lt $MAX ]; do
		LINE=(${TIMESTAMPS[$I]})
		STARTTIME="${LINE[0]}"
		CUT_START=$(add_frames $STARTTIME -1)
		ENDTIME="${LINE[1]}"
		CUT_END=$(add_frames $ENDTIME 1)
		SEGMENT="$LAST $CUT_START"
		LAST="$CUT_END"
		SEGMENTS+=("$SEGMENT")
		# Sort mods based on whether they belong to this segment or the next
		MODSTRING="${LINE[@]:2}"
		MODTHIS="$MODNEXT"
		MODNEXT=""
		for M in $MODSTRING; do
			case $M in
				fadeout=*|vfadeout=*|afadeout=*)
					MODTHIS="$MODTHIS $M"
					;;
				fadein=*|vfadein=*|afadein=*)
					MODNEXT="$MODNEXT $M"
					;;
				*)
					echo "Unknown modifier: $M" 1>&2
					echo "Cuts file: \"$CUTS_FILE\"" 1>&2
					exit 1
					;;
			esac
		done
		MODIFIERS+=("$MODTHIS")
		I=$((I+1))
	done
	SEGMENTS+=("$LAST end")
	MODIFIERS+=("$MODNEXT")
}

debug "Found ${#SEGMENTS[@]} segments"

# Where the complex_filter string gets built. Eventually contains the complete string.
FILTER=""
# A simple character lookup because the "endpoint" names in the complex filter aren't liking
# numbers in them, so instead of "seg0_stream0", I'm doing "sega_streama" using this array to
# convert the int to a char.
CHARS=(a b c d e f g h i j k l m)
# Stores the "endpoint" names that should get concatenated.
CONCATS=""

# Iterate the SEGMENTS and build filter lines for each of them.
SEGCOUNT="0"
I=0
while [ $I -lt "${#SEGMENTS[@]}" ]; do
	SEGSTRING="${SEGMENTS[$I]}"
	MODS=(${MODIFIERS[$I]})
        SEGMENT=($SEGSTRING)
        START_S="${SEGMENT[0]}"
        END_S="${SEGMENT[1]}"
        debug "Segment: $START_S - $END_S with modifiers: ${MODS[@]}"
        STREAMCOUNT="0"
        for STREAM in "${CUT_STREAMS[@]}"; do
                [ "$STREAM" = "0:0" ] && AORV="" || AORV="a"
    	        EXTRA_FILTERS=""
	        [ "$STREAM" = "0:0" ] && [ -n "$EXTRA_VFILTERS" ] && EXTRA_FILTERS=",$EXTRA_VFILTERS"
		# Name of the output for the latest link of the filter chain. Modifications might mutate this to add additional links.
	        # At the end, the value of this var is used as input to the concat filter for this stream.
                OUTPUT="p${CHARS[$I]}_s${CHARS[STREAMCOUNT]}"
                [ "$END_S" = "end" ] && {
       	                FILTER="$FILTER [$STREAM]${AORV}trim=start=$START_S,${AORV}setpts=PTS-STARTPTS${EXTRA_FILTERS}[$OUTPUT];"
               	} || {
                       	FILTER="$FILTER [$STREAM]${AORV}trim=start=$START_S:end=$END_S,${AORV}setpts=PTS-STARTPTS${EXTRA_FILTERS}[$OUTPUT];"
                }
		for M in "${MODS[@]}"; do
			debug "  apply $M to stream $STREAM"
			NEWOUTPUT="${OUTPUT}_mod"
			case $M in
				fadeout=*)
					DURATION="${M#fadeout=}"
					FADESTART=$(echo "$END_S - $START_S - $DURATION" | bc)
					FILTER="$FILTER [$OUTPUT]${AORV}fade=t=out:st=$FADESTART:d=$DURATION[$NEWOUTPUT];"
					OUTPUT="$NEWOUTPUT"
					;;
				vfadeout=*)
					[ "$STREAM" = "0:0" ] && {
						SETTINGS="${M#vfadeout=}"
                	                        SEGLENGTH=$(echo "$END_S - $START_S" | bc)
						[[ "$SETTINGS" =~ ^[0-9.]+$ ]] && {
							DURATION="$SETTINGS"
							FADESTART=$(echo "$SEGLENGTH - $DURATION" | bc)
        	                                	FILTER="$FILTER [$OUTPUT]${AORV}fade=t=out:st=$FADESTART:d=$DURATION[$NEWOUTPUT];"
						} || {
							IFS=':' read -ra PARAMS <<< "$SETTINGS"
							FILTER="$FILTER [$OUTPUT]${AORV}fade=t=out"
							for P in "${PARAMS[@]}"; do
								if [[ "$P" =~ ^st= ]]; then
									REQUESTED_START="${P#st=}"
									FADESTART=$(echo "$SEGLENGTH + $REQUESTED_START" | bc)
									FILTER="$FILTER:st=$FADESTART"
								else
									FILTER="$FILTER:$P"
								fi
							done
							FILTER="$FILTER[$NEWOUTPUT];"
						}
	                                        OUTPUT="$NEWOUTPUT"
					}
					;;
				afadeout=*)
					[ "$STREAM" = "0:0" ] || {
                        	                DURATION="${M#afadeout=}"
                	                        FADESTART=$(echo "$END_S - $START_S - $DURATION" | bc)
        	                                FILTER="$FILTER [$OUTPUT]${AORV}fade=t=out:st=$FADESTART:d=$DURATION[$NEWOUTPUT];"
	                                        OUTPUT="$NEWOUTPUT"
					}
					;;
				fadein=*)
					DURATION="${M#fadein=}"
					FILTER="$FILTER [$OUTPUT]${AORV}fade=t=in:d=$DURATION[$NEWOUTPUT];"
					OUTPUT="$NEWOUTPUT"
					;;
				vfadein=*)
					[ "$STREAM" = "0:0" ] && {
						SETTINGS="${M#vfadein=}"
						[[ "$SETTINGS" =~ ^[0-9.]+$ ]] && {
							FILTER="$FILTER [$OUTPUT]${AORV}fade=t=in:d=$SETTINGS[$NEWOUTPUT];"
						} || {
							FILTER="$FILTER [$OUTPUT]${AORV}fade=t=in:$SETTINGS[$NEWOUTPUT];"
						}
						OUTPUT="$NEWOUTPUT"
					}
					;;
				afadein=*)
					[ "$STREAM" = "0:0" ] || {
						DURATION="${M#afadein=}"
						FILTER="$FILTER [$OUTPUT]${AORV}fade=t=in:d=$DURATION[$NEWOUTPUT];"
						OUTPUT="$NEWOUTPUT"
					}
					;;
				*)
					echo "Unknown mod: $M" 1>&2
					exit 1
					;;
			esac
		done
                CONCATS="${CONCATS}[$OUTPUT]"
                STREAMCOUNT=$((STREAMCOUNT+1))
        done
        SEGCOUNT=$((SEGCOUNT+1))
	I=$((I+1))
done

# Holds the names of the concatenated streams that need to be mapped into the final output
FINAL_STREAMS=""
# Holds the -map args to use for mapping the FINAL_STREAMS
MAPS=""
for I in $(seq 0 $(("${#CUT_STREAMS[@]}"-1))); do
        OUTPUT="[out${CHARS[$I]}]"
        FINAL_STREAMS="$FINAL_STREAMS$OUTPUT"
        MAPS="$MAPS -map $OUTPUT"
done

# The complete filter
FILTER="$FILTER ${CONCATS}concat=n=${SEGCOUNT}:v=1:a=$((STREAMCOUNT-1))$FINAL_STREAMS"

echo "$FILTER"

