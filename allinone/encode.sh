#!/bin/bash -e

script_dir="$(cd "$(dirname "$0")" && pwd)"
export script_dir

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
INPUTDIR=${INPUTDIR:-"/mnt/l/ripping"}
export INPUTDIR
# Root directory of movies library, where final transcoded movies go, possibly in a subdirectory to organize
# related items the way Plex likes them.
MOVIESDIR=${MOVIESDIR:-"/mnt/plex-media/encoded/movies"}
export MOVIESDIR
# Root directory of tv shows library, where final transcoded shows go.
TVSHOWSDIR=${TVSHOWSDIR:-"/mnt/plex-media/encoded/tv-shows"}
export TVSHOWSDIR
# Directory holding general ripping tools
TOOLSDIR=${TOOLSDIR:-"$script_dir/.."}
export TOOLSDIR

die() {
  echo "ERROR: $1" >&2
  exit 1
}
export -f die

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
  [[ "$DEBUG" =~ "encode" ]] && echo -e "$1" 1>&2
  return 0
}
export -f debug

debug "Running from $script_dir"

function cleanup {
  if [ -n "${output_tmp_paths[*]}" ]; then
    for i in "${!output_tmp_paths[@]}"; do
      status=clean_it
      tmp_output="${output_tmp_paths[i]}"
      if [ -f "$tmp_output" ]; then
        echo "Checking if we should should keep or clean up '$tmp_output'"
        j=$((i+1))
        next_tmp_output="${output_tmp_paths[j]}"
        if [ -n "$next_tmp_output" ] && [ -f "$next_tmp_output" ]; then
          size="$(cat "$next_tmp_output" | wc -c)"
          # Check for non-trivial size. In practice, non-started files seem to end up about 5k?
          if [ "$size" -gt 102400 ]; then
            # The current one must have finished because the next one was at least started
            status=keep_it
          fi
        fi
        if [ "$status" = keep_it ]; then
          abs_output="${output_abs_paths[i]}"
          done_file="${done_files[i]}"
          echo "It's done! Keep it!"
          mv "$tmp_output" "$abs_output" && touch "$done_file"
        else
          echo "Doesn't look done. Trash it!"
          rm -f "$tmp_output"
        fi
      fi
    done
  fi
}
export -f cleanup

function encode_one {
  [ -f "$1" ] || {
    echo "File doesn't exist: '$1'" 2>&1
    exit 1
  }
  set -e
  # Absolute path to the input file
  input_abs_path="$(realpath "$1")"

  # Verify pixel format because I have to specify it for GPU encoding, and I'm not certain what happens if you change it.
  in_pix_fmt="$(ffprobe -v error -select_streams v:0 -show_entries stream=pix_fmt -of default=noprint_wrappers=1:nokey=1 "$input_abs_path")"
  [ "$in_pix_fmt" = "yuv420p" ] || die "Only handling pixel format yuv42p. Input has format '$in_pix_fmt'"

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
  # shellcheck disable=SC1090
  source "$main_config" || {
    echo "Failed to source $main_config" >&2
    exit 1
  }
  debug "Using config: $config_file"
  # shellcheck disable=SC1090
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
  # movie or tv show.
  #
  # The second part comes from the variable MAIN_NAME.
  #
  # The third part comes primarily from the variable OUTPUTNAME.
  # from the file-specific config file. For tv shows there's an,
  # alternate path where we can built the relative output path
  # based on the variables SEASON and EPISODE. In addition,
  # SEASON is optional if it can be inferred from the input path.
  [ -n "$MAIN_NAME" ] || {
    echo "Missing MAIN_NAME from configuration. It should be set in the main config" >&2
    echo "file for the title at: $main_config" >&2
    exit 1
  }

  # Wait, as a special case, tv show inputs will likely have the
  # season in the input path, so look for it there if it's not in
  # the config.
  season_regex="[/ ](Season|SEASON) ([[:digit:].]+)[/ ]"
  if [ -z "$SEASON" ] && [[ "$input_rel_path" =~ $season_regex ]]; then
    SEASON="${BASH_REMATCH[2]}"
  fi

  if [ -n "$OUTPUTNAME" ]; then
    output_rel_path="$MAIN_NAME/$OUTPUTNAME"
  elif [ -n "$SEASON" ] && [ -n "$EPISODE" ]; then
    # This only does 2-digit season and episode; probably need to
    # allow for three at some point. Do it always? Or based on
    # config?
    padded_season="$(printf %.2d ${SEASON#0})"
    padded_episode="$(printf %.2d ${EPISODE#0})"
    output_rel_path="$MAIN_NAME/Season $SEASON/$MAIN_NAME s${padded_season}e${padded_episode}.mkv"
  else
    echo "Missing fields from config: $config_file" >&2
    echo "It must contain either:" >&2
    echo "1. OUTPUTNAME, giving the relative path of the output file, or" >&2
    echo "2. both SEASON and EPISODE for a tv show so that an output path can be built." >&2
    echo "   (Except if the input path contains /Season xxx/, then SEASON can come from there." >&2
    exit 1
  fi

  # Also check for season in the output path! If the disks aren't ripped into the typical "tv show" structure,
  # but have an OUTPUTNAME that puts the outputs in that structure, the output would have a season in it.
  if [ -z "$SEASON" ] && [[ "$output_rel_path" =~ $season_regex ]]; then
    SEASON="${BASH_REMATCH[1]}"
  fi

  # Now figure out if we're encoding a movie or a tv episode. We an make a guess based on whether a "season" is
  # involved.
  if [ -n "$SEASON" ]; then
    MAIN_TYPE_GUESS=tvshow
  else
    MAIN_TYPE_GUESS=movie
  fi

  # If the MAIN_TYPE isn't configured (usually isn't), then fall back to our guess.
  [ -z "$MAIN_TYPE" ] && MAIN_TYPE="$MAIN_TYPE_GUESS"

  # Based on what we know about the type, decide whether to put it in the movies output dir or the tv output dir.
  if [ "$MAIN_TYPE" = movie ]; then
    base_output_dir="$MOVIESDIR"
  elif [ "$MAIN_TYPE" = tvshow ] || [ "$MAIN_TYPE" = tv_show ]; then
    # If it's a tv special, we might want to store it under a movie for organization. Plex is bad at handling tv
    # specials.
    if [ "$SPECIAL_TYPE" = movie ] && [ -n "$OUTPUTNAME" ] && ! [[ "$OUTPUTNAME" =~ ^Season ]]; then
      base_output_dir="$MOVIESDIR"
      required_file="$base_output_dir/$MAIN_NAME/$MAIN_NAME.mkv"
      [ -f "$required_file" ] || \
        die "Need a bogus movie file to support tv specials as movies! at: $required_file"
    else
      base_output_dir="$TVSHOWSDIR"
    fi
  else
    die "No MAIN_TYPE configured, and couldn't determine one."
  fi

  # Let some values be set in config. Otherwise, figure them out.
  [ -n "$INTERLACED" ] && CONFIG_INTERLACED="$INTERLACED"
  [ -n "$CROPPING" ] && CONFIG_CROPPING="$CROPPING"

  if [ -z "$CONFIG_INTERLACED" ] || [ -z "$CONFIG_CROPPING" ]; then
    analysis_cache_file="$CACHEDIR/analyze/$input_rel_path"
    if [ -f "$analysis_cache_file" ]; then
      debug "Using cached analysis: $analysis_cache_file"
      ANALYSIS="$(cat "$analysis_cache_file")"
    else
      echo "Analyzing..."
      echo " - $(date)"
      ANALYSIS=$("$TOOLSDIR/analyze.sh" "$input_abs_path" -k "$input_rel_path")
      mkdir -p "$(dirname "$analysis_cache_file")" \
        && echo "$ANALYSIS" > "$analysis_cache_file" \
        || die "Failed to write analysis to cache: $analysis_cache_file"
      echo " - $(date)"
    fi
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

  # Okay, at this point, I think we've gathered all the information
  # we need about the input video. Now on to figuring out what to do
  # with it.

  # New stuff: I think it could be helpful to track the title length
  # and possibly the checksum of inputs so we can more easily identify
  # them in the future. Think of the case where we rip a disk with
  # makemkv with different "minimum title length" settings. The file
  # names would change, but the lengths of the titles ought to stay
  # the same. Hopefully the checksums will, too, but I'm not
  # confident about that, especially across makemkv releases.

  details_file="$DATADIR/details/$input_rel_path"
  if [ ! -f "$details_file" ]; then
    debug "Gathering title details"
    input_size=$(du -b "$input_abs_path" | awk '{print $1}')
    debug "Size: $input_size"
    debug "Duration: $input_length"
    echo "Recording details to $details_file"
    mkdir -p "$(dirname "$details_file")"
    cat <<EOF > "$details_file"
ORIGINAL_DURATION=$input_length
ORIGINAL_SIZE=$input_size
EOF
  fi

  if [ -f "$DATADIR/cuts/$input_rel_path" ]; then
    # Note: cuts were added before splitting and are based on input path. I have to rethink how this works with splitting.
    [ "$SPLIT" = true ] && die "Can't use cuts with splits until I rewrite this!"
    concat_cache_file="$CACHEDIR/concat/$input_rel_path"
    FILTERCMD=("$script_dir/filter.sh" "$input_abs_path" -c "$concat_cache_file")
    EXTRAS=()
    [ "$INTERLACED" = "interlaced" ] && EXTRAS+=("yadif")
    [ "$CROPPING" = none ] || EXTRAS+=("crop=$CROPPING")
    [ -n "$EXTRAS" ] && FILTERCMD+=(-v "$(IFS=,; printf "%s" "${EXTRAS[*]}")")
    mkdir -p "$(dirname "$concat_cache_file")"
    printable=""
    for x in "${FILTERCMD[@]}"; do
      printable+="'$x' "
    done
    debug "Calculate filter args with: $printable"
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
  encodings=()
  if [ -n "$COMPLEXFILTER" ]; then
    debug "have complex filter; mapping this way"
    s_idx=0
    ALLOUTS=($OUTSTRING)
    while read -r line; do
      if [[ "$line" =~ Stream\ #(.:.+)\([^\)]*\):\ (Video|Audio|Subtitle): ]]; then
        stream="${BASH_REMATCH[1]}"
        stream_type="${BASH_REMATCH[2]}"
        case "$stream_type" in
          Video)
            debug "Map stream $stream as video"
            MAPS="$MAPS -map ${ALLOUTS[$s_idx]}"
            # Video encoding settings are handled later, though it assumes only a single video stream.
            ;;
          Audio)
            debug "Map stream $stream as audio"
            MAPS="$MAPS -map ${ALLOUTS[$s_idx]}"
            encodings+=("-c:$s_idx" "ac3" "-ac:$s_idx" "6" "-b:$s_idx" "384k")
            ;;
          Subtitle)
            debug "Map stream $stream as subtitle"
            MAPS="$MAPS -map 1:$s_idx"
            # No encoding for subtitle streams. They're handled by the concat file.
            ;;
          *)
            echo "Stream $stream has unkown type $stream_type" >&2
            exit 1
            ;;
        esac
      elif [[ "$line" =~ mjpeg\ .*\(attached\ pic\) ]]; then
        :
      else
        echo "Couldn't detect stream type" >&2
        exit 1
      fi
      s_idx=$((s_idx+1))
    done <<<"$(ffprobe -probesize 100M -i "$input_abs_path" 2>&1 | grep Stream)"
#    	NMAPS="${#CUT_STREAMS[@]}"
#    	NMAPS=$((NMAPS-1))
#    	for I in $(seq 0 $NMAPS); do
#    	    MAPS="$MAPS -map ${ALLOUTS[$I]}"
#    	done
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

  # Check if the input title needs to be split. If so, the output path is dynamic and has to be recalculated for each
  # output. The output_rel_path will contain a numeric printf format specifier that will be replaced by the count of the
  # output based on splits. Do that before using the output path for anything! I.e. the first output file will get
  # number 1, the second number 2, etc.
  if [ "$SPLIT" = true ]; then
    [ -n "${SPLIT_CHAPTER_STARTS[*]}" ] ||
      die "Config calls for splitting, but no SPLIT_CHAPTER_STARTS is set"
    [ -n "$SPLIT_START_NUMBER" ] ||
      die "Config calls for splitting, but no SPLIT_START_NUMBER is set"
    chapter_times_raw=$("$TOOLSDIR/chapters.sh" -i "$input_abs_path") ||
      die "Failed to read chapter times from input"
    IFS=' ' read -r -a chapter_times <<< "$chapter_times_raw"
    split_times=()
    for chapter in "${SPLIT_CHAPTER_STARTS[@]}"; do
      split_times+=("${chapter_times[$chapter]}")
    done
    debug "Splitting video at chapters ${SPLIT_CHAPTER_STARTS[*]}"
    debug "  which corresponds to timestamps ${split_times[*]}"
  else
    split_times=(0)
  fi

  [ "$QUALITY" = "rough" ] && {
    output_rel_path="${output_rel_path//\//_}"
    base_output_dir="$TOOLSDIR"
  }

  which_split=0
  next_split=1
  # Guarantee we enter the loop
  split_start_time="${split_times[$which_split]:-0}"
  output_args=()
  output_tmp_paths=()
  output_abs_paths=()
  done_files=()
  # Main loop to build output specs. It's this complicated to support splitting one input into multiple outputs (looking
  # at you, Chuck bluray Season 2!!).
  while [ -n "$split_start_time" ]; do
    # If the starting chapter is zero, and therefore the start timestamp is 0 (something like 0:00:00.00000), then omit
    # the -ss to naturally start from the beginning of the input. This will also be the case if we're not splitting.
    if ! [[ "$split_start_time" =~ ^[0:.]*$ ]]; then
      output_args+=(-ss "$split_start_time")
    fi
    # If there are more splits to do, then the next entry in the split_times array will have the time of the end of the
    # next split.
    to_time="${split_times[$next_split]}"
    if [ -n "$to_time" ]; then
      output_args+=(-to "$to_time")
    fi
    # If we've added anything to output_args, we're doing splits, so format the output name
    if [ -n "${output_args[*]}" ]; then
      output_video_num=$((SPLIT_START_NUMBER + which_split))
      formatted_output_rel_path="$(printf "$output_rel_path" "$output_video_num")"
    else
      # In this case, we're not splitting - the start time was 0, and there was no "next"
      formatted_output_rel_path="$output_rel_path"
    fi

    output_abs_path="$base_output_dir/$formatted_output_rel_path"
    output_tmp_path="$base_output_dir/$(dirname "$formatted_output_rel_path")/$(basename "$formatted_output_rel_path").part"

    done_file="$DONEDIR/$formatted_output_rel_path"
    already_done=false
    debug "Check if already done; done file: $done_file"
    [ -f "$done_file" ] && already_done=true
    [ -f "$output_abs_path" ] || already_done=false
    if [ $already_done = true ]; then
      echo "Done: $input_rel_path -> $output_abs_path" >&2
    else
      echo "Processing $input_rel_path into $output_abs_path" >&2
      # This because several videos end up failing with the "Too many packets buffered for output stream XXX" error.
      # I don't think this will cause any problems.
      output_args+=(-max_muxing_queue_size 1024)
      # Use one filter or the other, if set. Setting both will cause an error, but that's checked earlier, and even if it's not,
      # ffmpeg will tell you what you did wrong.
      [ -z "$COMPLEXFILTER" ] || output_args+=(-filter_complex "$COMPLEXFILTER")
      output_args+=($MAPS -c copy)
      if [ -n "$VFILTERSTRING" ]; then
        if [ -n "$USE_GPU" ]; then
          output_args+=("-filter:v:0" "hwdownload,format=nv12,$VFILTERSTRING,hwupload_cuda")
        else
          output_args+=("-filter:v:0" "$VFILTERSTRING")
        fi
      fi

      # Do real video encoding, or speed encode for checking the output?
      if [ "$QUALITY" = "rough" ]; then
        #output_args+=(-c:0 mpeg2video -threads:0 2)
        output_args+=(-c:0 libx264 -preset ultrafast)
      else
        if [ -n "$USE_GPU" ] && [ -z "$NEVER_GPU" ]; then
          output_args+=(-c:0 hevc_nvenc)
        else
          output_args+=(-c:0 libx265 -crf:0 "$VQ")
        fi
      fi
      if [ "$QUALITY" != "rough" ] && [ -n "$TRANSCODE_AUDIO" ]; then
        output_args+=(-c:1 ac3 -ac:1 6 -b:1 384k)
      fi

      output_args+=(-metadata:s:0 "encoded_by=My smart encoder script")
      if [ "$QUALITY" != "rough" ] && [ -n "$TRANSCODE_AUDIO" ]; then
        output_args+=(-metadata:s:1 "title=Transcoded Surround for Sonos")
      fi
      output_args+=($FFMPEG_EXTRA_OPTIONS)

      output_args+=(-f matroska "$output_tmp_path")
      output_tmp_paths+=("$output_tmp_path")
      output_abs_paths+=("$output_abs_path")
      done_files+=("$done_file")
      debug "Created outputs for: '$output_tmp_path'"
    fi

    if [ -n "$ONLY_MAP" ]; then
      echo "IN: $input_abs_path OUT: $output_abs_path"
    fi

    which_split=$((which_split+1))
    next_split=$((which_split+1))
    split_start_time="${split_times[$which_split]}"
  done

  debug "Splitting into $which_split outputs"

  if [ -n "$ONLY_MAP" ]; then
    return 0
  fi

  if [ -z "${output_abs_paths[*]}" ]; then
    return 0
  fi

  # Just to be safe, unset the temp vars that were used above so that we don't confuse them with anything later on.
  unset output_abs_path output_tmp_path formatted_output_rel_path done_file already_done

  trap cleanup EXIT

  # Always display the movie length because I use that to gauge
  # progress when watching the logs.
  input_length=$(ffprobe -v error -select_streams v:0 -show_entries stream_tags=DURATION-eng -of default=noprint_wrappers=1:nokey=1 "$input_abs_path" | cut -d '.' -f 1)
  echo "Duration: $input_length"

  # Use locally installed ffmpeg, or a docker container?
  CMD=(ffmpeg)
  #CMD=(docker run --rm -v "$TOOLSDIR":"$TOOLSDIR" -v "$MOVIESDIR":"$MOVIESDIR" -w "$(pwd)" jrottenberg/ffmpeg -stats)

  [ -n "$USE_GPU" ] && ! [ "$NEVER_GPU" ] && CMD+=(-hwaccel cuda -hwaccel_output_format cuda)
  CMD+=(-hide_banner -y -i "$input_abs_path")

  # If doing cuts, use the concat file to attach cut subtitles from the input file
  if [ -n "$COMPLEXFILTER" ]; then
    CMD+=(-safe 0 -f concat -i "$concat_cache_file")
  fi

  # If cutting is happening, encodings to apply will have been calculated previously. You can't do any stream copies when using a
  # complex filtergraph, so every stream needs an encoding.
  [ -n "$COMPLEXFILTER" ] && {
    CMD=("${CMD[@]}" "${encodings[@]}")
  }

  CMD+=("${output_args[@]}")
  LOGFILE="$LOGDIR/$input_rel_path.log"

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

  for path in "${output_abs_paths[@]}"; do
    mkdir -p "$(dirname "$path")"
  done
  mkdir -p "$(dirname "$LOGFILE")"
  if [ -n "$DRYRUN" ]; then
    echo "  -- dry run requested, not running"
  else
    ln -fs "$LOGFILE" currentlog
    "${CMD[@]}" &> "$LOGFILE"
    encode_result="$?"
  fi
  echo " - $(date)"

  if [ "$QUALITY" = "rough" ]; then
    echo "Rough encode done, not marking file as done done."
  elif [ -n "$DRYRUN" ]; then
    echo "Dry run, not marking file as done done."
  elif [ "$encode_result" -eq 0 ]; then
    echo "Marking file as done done."
    for i in "${!output_abs_paths[@]}"; do
      output_tmp_path="${output_tmp_paths[i]}"
      output_abs_path="${output_abs_paths[i]}"
      done_file="${done_files[i]}"
      if [ -z "$output_tmp_path" ] || [ -z "$output_abs_path" ] || [ -z "$done_file" ]; then
        die "Something went horribly wrong: tmp='$output_tmp_path' abs='$output_abs_path' done='$done_file'"
      fi
      mv "$output_tmp_path" "$output_abs_path" && mkdir -p "$(dirname "$done_file")" && touch "$done_file"
    done
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
[ -z "$ONE" ] && "$script_dir/ls-inputs.sh" -sz | xargs -0I {} bash -c 'encode_one "{}"'
