#!/bin/bash -e

script_dir="$(cd "$(dirname "$0")" && pwd)"
echo "Running from $script_dir"

# Base directories that contain details of media processing. "cache" is for temporary things. These shouldn't be committed.
# "data" is where information is stored about how to process specific files. This should be committed. I normally keep these
# in the same directory as the script. "data" is committed there.
CACHEDIR="${CACHEDIR:-"$script_dir/cache"}"
export CACHEDIR
DATADIR="${DATADIR:-"$script_dir/data"}"
export DATADIR

# Contains named files representing files already encoded. Remove a file to make it get processed again.
DONEDIR="$CACHEDIR/done"
export DONEDIR
# Contains the ffmpeg logs to ensure an encode finished successfully
LOGDIR="$CACHEDIR/log"
export LOGDIR
# Contains config files with data for each movie file to be encoded.
CONFIGDIR=${CONFIGDIR:-"$DATADIR/config"}
export CONFIGDIR
# Directory to scan for raw mkv's ripped from disc
INPUTDIR=${INPUTDIR:-"/media/plex-media-2/ripping/media-in"}
export INPUTDIR
# Root directory of movies library, where final transcoded movies go, possibly in a subdirectory to organize
# related items the way Plex likes them.
MOVIESDIR=${MOVIESDIR:-"/media/plex-media/movies"}
export MOVIESDIR
# Root directory of tv shows library, where final transcoded shows go.
TVSHOWSDIR=${TVSHOWSDIR:-"/media/plex-media/tv-shows"}
export TVSHOWSDIR
# Directory holding general ripping tools
TOOLSDIR=${TOOLSDIR:-"/media/plex-media-2/ripping/tools"}
export TOOLSDIR

die() {
	echo "ERROR: $1" >&2
	exit 1
}

[ -d "$CACHEDIR" ] || die "CACHEDIR doesn't exist: $CACHEDIR"
[ -d "$DATADIR" ] || die "DATADIR doesn't exist: $DATADIR"
[ -d "$CONFIGDIR" ] || die "CONFIGDIR doesn't exist: $CONFIGDIR"
[ -d "$INPUTDIR" ] || die "INPUTDIR doesn't exist: $INPUTDIR"
[ -d "$MOVIESDIR" ] || die "MOVIESDIR doesn't exist: $MOVIESDIR"
[ -d "$TVSHOWSDIR" ] || die "TVSHOWSDIR doesn't exist: $TVSHOWSDIR"
[ -d "$TOOLSDIR" ] || die "TOOLSDIR doesn't exist: $TOOLSDIR"

# Ensure cache subdirectories exist.
mkdir -p "$DONEDIR"
mkdir -p "$LOGDIR"

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
    # Absolute path to the input file
    input_abs_path="$(realpath "$1")"

    # Now we have to figure out what config file to look for. The
    # input could be either a movie or a tv show. A movie file might
    # be:
    #
    # /media/blah/ripping/media-in/MenInBlack/title01.mkv
    #
    # A tv show would be more like:
    #
    # /media/blah/ripping/media-in/MASH/Season 4/Disk 2/title01.mkv
    #
    # In either case, removing the input dir from the front of the
    # file name gives us a path we can use to map to a config file. In
    # other words, the config file name matches the relative path to
    # the input file.
    input_rel_path="${input_abs_path#$INPUTDIR/}"

    # Now load the config file so that we can refer to the information
    # in it as needed. A config file is required for every input file
    # because we at least have to know the output name to use. For the
    # most part, it'll also give information about the streams to
    # encode. It's possible I could build something for tv shows that
    # would figure that out automatically. See the "profiles" I used
    # for encoding BSG, which used the details of the streams in an
    # episode as a signature to determine which streams should be
    # kept.
    config_file="$CONFIGDIR/$input_rel_path"

    # Also at the root of each show's or movie's input dir for a file
    # named "main" that contains key details for the whole show or
    # movie.
    main_config="$CONFIGDIR/${input_rel_path%%/*}/main"

    # Now get both configs loaded. Load main config first, in case
    # there's something I'd like to set at the top level but override
    # for certain files.
    [ -f "$config_file" ] || {
	echo "Missing config file: $config_file" >&2
	exit 1
    }
    [ -f "$main_config" ] || {
	echo "Missing main config file: $main_config" >&2
	exit 1
    }
    debug "Loading main config: $main_config"
    source "$main_config" || {
	echo "Failed to source $main_config" >&2
	exit 1
    }
    debug "Using config: $config_file"
    source "$config_file" || {
	echo "Failed to source $config_file" >&2
	exit 1
    }

    # Figure out what our output path is. This will be an absolute
    # path. For movies, it'll be like
    #
    # /media/blah/movies/Men In Black/Men In Black.mkv
    #
    # For tv shows, it'll be like
    #
    # /media/blah/tv-shows/MASH/Season 4/MASH s04e02.mkv
    #
    # There are three parts to the output path:
    #
    # - the base output path: /media/blah/[movies|tv-shows]
    # - the main movie or show name: "Men In Black" or "MASH"
    # - a relative path to a specific output file: "Men In Black.mkv"
    #   or "Season 4/MASH s04e02.mkv"
    #
    # The first part is always the same, based on whether this is a
    # movie or tv show. (How do we know that? I'm not sure yet.)
    #
    # The second part comes from the main config file in an entry
    # called MAIN_NAME.
    #
    # The third part comes from the file-specific config file. For a
    # movie, it'll be in a field named OUTPUTNAME. For a tv show,
    # there will be SEASON and EPISODE fields, and we can build the
    # output path. We'll look for OUTPUTNAME first and fall back to
    # SEASON/EPISODE. That gives us two options for interpreting the
    # data.
    #
    # One option is to say that if the config has an OUTPUTNAME, then
    # it's a movie, and if not, it's a tv show. The other option is
    # that we let tv shows use OUTPUTNAME in case we might need to
    # account for special cases in the future. If we go the latter
    # route, we need a different way to distinguish movie from tv
    # show, which will probably have to be a setting in the main
    # config file. Is there any other way to tell the difference?
    # Maybe if the final output path contains the string "/Season
    # \d+/"?
    [ -n "$MAIN_NAME" ] || {
	echo "Missing MAIN_NAME from configuration. It should be set in the main config" >&2
	echo "file for the title at: $main_config" >&2
	exit 1
    }

    # Wait, as a special case, tv show inputs will likely have the
    # season in the input path, so look for it there if it's not in
    # the config.
    rex="/Season ([[:digit:]]+)/"
    if [ -z "$SEASON" ] && [[ "$input_rel_path" =~ $rex ]]; then
	SEASON="${BASH_REMATCH[1]}"
    fi
    
    if [ -n "$OUTPUTNAME" ]; then
	output_rel_path="$MAIN_NAME/$OUTPUTNAME"
	base_output_dir="$MOVIESDIR"
    elif [ -n "$SEASON" ] && [ -n "$EPISODE" ]; then
	# This only does 2-digit season and episode; probably need to
	# allow for three at some point. Do it always? Or based on
	# config?
	padded_season="$(printf %.2d $SEASON)"
	padded_episode="$(printf %.2d $EPISODE)"
	output_rel_path="$MAIN_NAME/Season $SEASON/$MAIN_NAME s${padded_season}e${padded_episode}.mkv"
	base_output_dir="$TVSHOWSDIR"
    else
	echo "Missing fields from config: $config_file" >&2
	echo "It must contain either:" >&2
	echo "1. OUTPUTNAME, giving the relative path of the output file, or" >&2
	echo "2. both SEASON and EPISODE for a tv show so that an output path can be built." >&2
	echo "   (Except if the input path contains /Season xxx/, then SEASON can come from there." >&2
	exit 1
    fi

    # Okay, at this point, I think we've gathered all the information
    # we need about the input video. Now on to figuring out what to do
    # with it.

    [ "$QUALITY" = "rough" ] && {
	output_rel_path="$(echo "$output_rel_path" | sed "s#/#_#g")"
	base_output_dir="$TOOLSDIR"
    }

    output_abs_path="$base_output_dir/$output_rel_path"
    output_tmp_path="$base_output_dir/$(dirname "$output_rel_path")/$(basename "$output_rel_path").part"
    trap 'rm -f "$output_tmp_path"' EXIT

    DONEFILE="$DONEDIR/$output_rel_path"
    DONE=false
    debug "Check if already done; done file: $DONEFILE"
    [ -f "$DONEFILE" ] && DONE=true
    [ ! -f "$output_abs_path" ] && DONE=false
    [ "$ONE" != "true" ] && [ $DONE = true ] && {
	echo "Done: $input_rel_path -> $output_abs_path" >&2
	return 0
    }
    echo "Processing $input_rel_path into $output_abs_path" >&2

    # New stuff: I think it could be helpful to track the title length
    # and possibly the checksum of inputs so we can more easily identify
    # them in the future. Think of the case where we rip a disk with
    # makemkv with different "minimum title length" settings. The file
    # names would change, but the lengths of the titles ought to stay
    # the same. Hopefully the checksums will, too, but I'm not
    # confident about that, especially across makemkv releases.

    # Always display the movie length because I use that to gauge
    # progress when watching the logs.
    input_length=$(ffprobe -v error -select_streams v:0 -show_entries stream_tags=DURATION-eng -of default=noprint_wrappers=1:nokey=1 "$input_abs_path" | cut -d '.' -f 1)
    echo "Duration: $input_length"

    details_file="$DATADIR/details/$input_rel_path"
    if [ ! -f "$details_file" ]; then
        echo "Gathering title details including sha1sum, may take a while"
        input_sha1=$(sha1sum "$input_abs_path" | awk '{print $1}')
        input_size=$(du -b "$input_abs_path" | awk '{print $1}')

        echo "Size: $input_size"
        echo "Checksum: $input_sha1"
        echo "Recording details to $details_file"
        mkdir -p "$(dirname "$details_file")"
        cat <<EOF > "$details_file"
ORIGINAL_DURATION=$input_length
ORIGINAL_SIZE=$input_size
ORIGINAL_CHECKSUM=sha1:$input_sha1
EOF
    fi

    # Let some values be set in config. Otherwise, figure them out.
    [ -n "$INTERLACED" ] && CONFIG_INTERLACED="$INTERLACED"
    [ -n "$CROPPING" ] && CONFIG_CROPPING="$CROPPING"

    if [ -z "$CONFIG_INTERLACED" ] || [ -z "$CONFIG_CROPPING" ]; then
	echo "Analyzing..."
	echo " - $(date)"
	ANALYSIS=$("$TOOLSDIR/analyze.sh" "$input_abs_path" -k "$input_rel_path")
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

    VQ=$("$TOOLSDIR/quality.sh" "$input_abs_path")
    debug "Quality: $VQ"

    if [ -f "$DATADIR/cuts/$input_rel_path" ]; then
	FILTERCMD=("./filter.sh" "$input_abs_path")
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
	# Let KEEP_STREAMS=all mean map every stream. With ffmpeg and one input, a "-map 0" will do that.
	if [ "$KEEP_STREAMS" = all ]; then
	    KEEP_STREAMS=0
	fi
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

    [ -n "$USE_GPU" ] && ! [ "$NEVER_GPU" ] && CMD+=(-hwaccel cuda -hwaccel_output_format cuda)
    CMD+=(-hide_banner -y -i "$input_abs_path")

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
        if [ -n "$USE_GPU" ] && [ -z "$NEVER_GPU" ]; then
          CMD+=(-c:0 hevc_nvenc)
        else
          CMD+=(-c:0 libx265 -crf:0 "$VQ")
        fi
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
    CMD+=(-f matroska "$output_tmp_path")
    LOGFILE="$LOGDIR/$output_rel_path.log"
    DONEFILE="$DONEDIR/$output_rel_path"

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
    mkdir -p "$(dirname "$output_abs_path")"
    mkdir -p "$(dirname "$LOGFILE")"
    mkdir -p "$(dirname "$DONEFILE")"
    if [ -n "$DRYRUN" ]; then
	echo "  -- dry run requested, not running"
    else
	ln -fs "$LOGFILE" currentlog
	"${CMD[@]}" &> "$LOGFILE" && mv "$output_tmp_path" "$output_abs_path"
	encode_result="$?"
    fi
    echo " - $(date)"

    if [ "$QUALITY" = "rough" ]; then
        echo "Rough encode done, not marking file as done done."
    elif [ -n "$DRYRUN" ]; then
        echo "Dry run, not marking file as done done."
    elif [ "$encode_result" -eq 0 ]; then
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
