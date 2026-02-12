#!/bin/bash -e

script_dir="$(cd "$(dirname "$0")" && pwd)"
export script_dir

source "$script_dir/config"

source "$script_dir/utils"
export -f die

# Base directories that contain details of media processing. "cache" is for temporary things. These shouldn't be committed.
# "data" is where information is stored about how to process specific files. This should be committed. I normally keep these
# in the same directory as the script. "data" is committed there.
CACHEDIR="${CACHEDIR:-"$script_dir/cache"}"
export CACHEDIR
DATADIR="${DATADIR:-"$script_dir/data"}"
export DATADIR
LOCKDIR="${LOCKDIR:-"$CACHEDIR/locks"}"
export LOCKDIR

# Contains named files representing files already encoded. Remove a file to make it get processed again.
DONEDIR="$CACHEDIR/done"
export DONEDIR
# Contains the ffmpeg logs to ensure an encode finished successfully
LOGDIR="$CACHEDIR/log"
export LOGDIR
# Contains config files with data for each movie file to be encoded.
CONFIGDIR=${CONFIGDIR:-"$DATADIR/config"}
export CONFIGDIR
# Root directory of movies library, where final transcoded movies go, possibly in a subdirectory to organize
# related items the way Plex likes them.
MOVIESDIR=${MOVIESDIR:-"/mnt/plex-media/plex-media-server/encoded/movies"}
export MOVIESDIR
# Root directory of tv shows library, where final transcoded shows go.
TVSHOWSDIR=${TVSHOWSDIR:-"/mnt/plex-media/plex-media-server/encoded/tv-shows"}
export TVSHOWSDIR
# Directory holding general ripping tools
TOOLSDIR=${TOOLSDIR:-"$script_dir/.."}
export TOOLSDIR

function debug {
  [[ "$DEBUG" =~ "encode" ]] && echo -e "$1" 1>&2
  return 0
}
export -f debug

[ -d "$CACHEDIR" ] || die "CACHEDIR doesn't exist: $CACHEDIR"
[ -d "$DATADIR" ] || die "DATADIR doesn't exist: $DATADIR"
[ -d "$LOCKDIR" ] || die "LOCKDIR doesn't exist: $LOCKDIR"
[ -d "$CONFIGDIR" ] || die "CONFIGDIR doesn't exist: $CONFIGDIR"
[ -d "$MOVIESDIR" ] || die "MOVIESDIR doesn't exist: $MOVIESDIR"
[ -d "$TVSHOWSDIR" ] || die "TVSHOWSDIR doesn't exist: $TVSHOWSDIR"
[ -d "$TOOLSDIR" ] || die "TOOLSDIR doesn't exist: $TOOLSDIR"

if ! [ "$MODE" = FIRST_PASS ] && ! [ "$MODE" = STABLE ] && ! [ "$MODE" = POLISHED ]; then
  die "You have to set a MODE. There's no default yet. Choose one of: FIRST_PASS | STABLE | POLISHED.\n \
    WARNING!!! POLISHED may be EXTREMELY SLOW!"
fi

# Ensure cache subdirectories exist.
mkdir -p "$DONEDIR"
mkdir -p "$LOGDIR"

# List of outputs to build the map values from in the function. Can't be an array because those can't be exported.
OUTSTRING="[outa] [outb] [outc] [outd] [oute] [outf] [outg] [outh] [outi] [outj] [outkl] [outm] [outn] [outo] [outp] [outq]"
export OUTSTRING

# If DRYRUN is set, export it so the function sees it
[ -n "$DRYRUN" ] && export DRYRUN

debug "Running from $script_dir"

function cleanup {
  if [ -f "$lock_file" ] && [ "$locked_by_me" = true ]; then
    echo "Clean up lock file: '$lock_file'"
    rm -f "$lock_file"
  fi
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
  input_dir="$1"
  input_rel_path="$2"
  # Absolute path to the input file
  input_abs_path="$(realpath "$input_dir/$input_rel_path")"
  [ -f "$input_abs_path" ] || {
    echo "File doesn't exist: '$input_abs_path'" 2>&1
    return 1
  }
  set -e

  # This here for now because I can't export it
  if [ -n "$ALT_OUTPUT_DIRS" ]; then
    IFS=: read -ra alt_output_dirs <<<"$ALT_OUTPUT_DIRS"
    debug "Using additional dirs for determining finished status:"
    for dir in "${alt_output_dirs[@]}"; do
	debug " - $dir"
    done
  fi

  # Verify pixel format because I have to specify it for GPU encoding, and I'm not certain what happens if you change it.
  in_pix_fmt="$(ffprobe -v error -select_streams v:0 -show_entries stream=pix_fmt -of default=noprint_wrappers=1:nokey=1 "$input_abs_path")"
  if [ -n "$USE_GPU" ] && [ -z "$NEVER_GPU" ]; then
    [ "$in_pix_fmt" = "yuv420p" ] || {
      echo "Only handling pixel format yuv42p. Input has format '$in_pix_fmt'" >&2
      echo " - path: $input_abs_path" >&2
      exit 1
    }
  fi

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

  output_args=()
  output_tmp_paths=()
  output_abs_paths=()
  done_files=()
  # First loop to determine outputs. It's this complicated to support splitting one input into multiple outputs (looking
  # at you, Chuck bluray Season 2!!). This only reads config data, figures out if we're splitting, and then determines
  # which of the outputs, if any, are already done. It stores everything else in the above variables so that a later
  # loop can build up the commands for creating the correct outputs.
  #
  # It's done in two parts this way so that input locking can happen after determining "done" and before we have to do
  # anything that causes side effects, like analyze.
  for i in "${!split_times[@]}"; do
    if [ "$SPLIT" = true ]; then
      output_video_num=$((SPLIT_START_NUMBER + i))
      formatted_output_rel_path="$(printf "$output_rel_path" "$output_video_num")"
    else
      formatted_output_rel_path="$output_rel_path"
    fi

    output_abs_path="$base_output_dir/$formatted_output_rel_path"
    output_tmp_path="$base_output_dir/$(dirname "$formatted_output_rel_path")/$(basename "$formatted_output_rel_path").part"

    done_file="$DONEDIR/$MODE/$formatted_output_rel_path"
    already_done=false
    debug "Check if already done; done file: $done_file"
    if [ -f "$done_file" ]; then
      debug "  done file exists"
      already_done=true
    fi
    output_exists=false
    [ -f "$output_abs_path" ] && output_exists=true
    for dir in "${alt_output_dirs[@]}"; do
	    [ -f "$dir/$formatted_output_rel_path" ] && output_exists=true
    done

    if [ "$output_exists" = false ]; then
      debug "  output doesn't exist"
      already_done=false
    fi
    debug "  already done = $already_done"

    if [ "$already_done" = true ] && [ -z "$FORCE" ]; then
      echo "Done: $input_rel_path -> $output_abs_path" >&2
      return 0
    else
      output_tmp_paths+=("$output_tmp_path")
      output_abs_paths+=("$output_abs_path")
      done_files+=("$done_file")
    fi

    if [ -n "$ONLY_MAP" ]; then
      echo "IN: $input_abs_path OUT: $output_abs_path"
    fi
  done

  debug "Splitting into ${#output_abs_paths[@]} outputs"

  if [ -n "$ONLY_MAP" ]; then
    return 0
  fi

  if [ -z "${output_abs_paths[*]}" ]; then
    return 0
  fi

  # We've figured out all we can and know whether we need to actually encode the video now. If we've made it here, we're
  # doing the encode, so lock the input so that other instances can't try to process the same file.
  lock_key="$(echo "$input_abs_path" | sed -r "s/[:/ '\"]+/_/g")"
  lock_file="$LOCKDIR/$lock_key"
  echo "Locking '$input_rel_path' as $lock_key" >&2
  if ! ( set -o noclobber; true >"$lock_file" ) &>/dev/null; then
    echo "Someone already locked '$input_rel_path'" >&2
    return 0
  fi
  locked_by_me=true

  # Let some values be set in config. Otherwise, figure them out.
  [ -n "$INTERLACED" ] && CONFIG_INTERLACED="$INTERLACED"
  [ -n "$CROPPING" ] && CONFIG_CROPPING="$CROPPING"

  if [ -z "$CONFIG_INTERLACED" ] || [ -z "$CONFIG_CROPPING" ]; then
    analysis_cache_file="$CACHEDIR/analyze/$input_rel_path"
    if [ -f "$analysis_cache_file" ]; then
      debug "Using cached analysis: $analysis_cache_file"
      ANALYSIS="$(cat "$analysis_cache_file")"
    else
      echo "Analyzing $input_rel_path"
      echo " - $(date)"
      ANALYSIS=$("$TOOLSDIR/analyze.sh" "$input_abs_path" -k "$input_rel_path") || \
        die "Analysis failed on '$input_abs_path'"
      ( mkdir -p "$(dirname "$analysis_cache_file")" && echo "$ANALYSIS" > "$analysis_cache_file" ) || \
        die "Failed to write analysis to cache: $analysis_cache_file"
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
    echo " - rel path: $input_rel_path" >&2
    echo " - config  : $config_file" >&2
    exit 1
  }
  debug "Cropping: $CROPPING"
  [ -z "$CROPPING" ] && {
    echo "No cropping determined. There should always be a value here." >&2
    echo " - rel path: $input_rel_path" >&2
    echo " - config  : $config_file" >&2
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

  # Grab info about the input file streams because I'll (probably) need it in more than one place. I could probably
  # speed things up by sharing this with utility scripts, too.
  stream_data="$(ffprobe -probesize 100M -i "$input_abs_path" 2>&1 | grep Stream)"

  # Listed here for my reference. Should I separate upscale from cleanup? Reportedly deinterlacing happens before
  # upscaling, so I guess I'm okay for now. Reconsider if I find something that should come after upscaling but before
  # noise reduction/sharpening.
  #
  # Make sure widths and heights are divisible by 2 for the yuv420 pixel format (w=-2 and h=-2 ensure this).

  # Best denoising for DVDs with slightly gentler unsharpening
  dvd_upscale_super_slow="zscale=w=-2:h=1080:filter=spline36:dither=error_diffusion,nlmeans=s=4:p=7:pc=0:r=15:rc=0,unsharp=5:5:0.5:5:5:0.25"
  # Faster denoising with a little more aggressive unsharpening. This is MASSIVELY faster!
  dvd_upscale_width_quick="zscale=w=1920:h=-2:filter=spline36:dither=error_diffusion,hqdn3d=1.5:1.5:6:6,unsharp=5:5:0.6:5:5:0.3"
  dvd_upscale_height_quick="zscale=w=-2:h=1080:filter=spline36:dither=error_diffusion,hqdn3d=1.5:1.5:6:6,unsharp=5:5:0.6:5:5:0.3"
  # For if I want to upscale bluray to 4k, but this will increase the file size a lot (maybe double)
  bluray_upscale="zscale=w=-2:h=2160:filter=spline36:dither=error_diffusion,hqdn3d=1.0:1.0:4:4,unsharp=5:5:0.4:5:5:0.2"
  # For now, I'm not even considering doing an nlmeans bluray upscale because of how insanely long it'll take.

  # I think this is a good place to adjust for the MODE we're in. We've figured out most stuff and are about to use it.
  if [ "$MODE" = FIRST_PASS ]; then
    debug "Tweaking settings for speed for MODE=FIRST_PASS"
    # Force no deinterlacing for speed
    INTERLACED=progressive
    # Keep cropping because in theory, encoding less pixels will be faster
    # x264 is faster than x265
    encoder=libx264
    encoder_settings=(-preset:v:0 ultrafast)
    # For first pass, we're going for small and fast. A higher CRF gives us small.
    VQ=28
  elif [ "$MODE" = STABLE ]; then
    debug "Relying on discovered settings for MODE=STABLE"
    encoder=libx265
    encoder_settings=(-preset:v:0 slow)
    # 10-bit is recommended for good color gradients
    # Setting pools manually to support docker containers where ffmpeg can't always detect the number of cores
    encoder_settings+=(-pix_fmt yuv420p10le -x265-params "pools=$(nproc)")

    # To upscale correctly, we need to know about the incoming video size.
    video_stream="$(echo "$stream_data" | grep 'Stream #0:0')"
    [ -n "$video_stream" ] || die "Didn't find video stream in stream data"
    # This seems to be what blurays look like
    # regex='Stream #0:0.*Video:.*, ([0-9]*)x([0-9]*) \[.*\], ([0-9.]*) fps, ([0-9.]*) tbr,.*$'
    # And this is what DVDs look like
    # regex='Stream #0:0.*Video:.*, ([0-9]*)x([0-9]*) \[.*\], SAR [0-9:]* DAR [0-9:]*, ([0-9.]*) fps, ([0-9.]*) tbr,.*$'
    # This handles both
    regex='Stream #0:0.*Video:.*, ([0-9]*)x([0-9]*) \[.*\].*, ([0-9.]*) fps, ([0-9.]*) tbr,.*$'
    if [[ "$CROPPING" =~ ^([0-9]*):([0-9]*):[0-9]*:[0-9]*$ ]]; then
      # If we're cropping the video, this is the size we need to look at, but cropping could be "none"
      width="${BASH_REMATCH[1]}"
      height="${BASH_REMATCH[2]}"
    elif [[ "$video_stream" =~ $regex ]]; then
      # If not cropping, then use the size of the incoming video
      width="${BASH_REMATCH[1]}"
      height="${BASH_REMATCH[2]}"
    else
      die "Couldn't determine input height and width"
    fi
    [ "$width" -gt 0 ] || die "Didn't get a good width, was '$width'"
    [ "$height" -gt 0 ] || die "Didn't get a good height, was '$height'"

    if [ "$width" -lt 1000 ]; then
      # Nearly half the width of 1080p (1920x1080), so let's upscale.
      debug "Upscaling DVD content"
      target_ratio="$(echo "1920/1080" | bc -l)"
      actual_ratio="$(echo "$width/$height" | bc -l)"
      if [ "$(echo "$actual_ratio > $target_ratio" | bc -l)" = 1 ]; then
        # Width dominates actual ratio, so scale to width
       upscale_filters="$dvd_upscale_width_quick"
      else
        # Height dominates actual ratio
       upscale_filters="$dvd_upscale_height_quick"
      fi
    fi
  else
    # Later, add support for POLISHED with the slow denoiser for DVD and possibly upscaling for bluray
    die "Unsupported MODE: '$MODE'"
  fi

  if [ -f "$DATADIR/cuts/$input_rel_path" ]; then
    [ -z "$upscale_filters" ] || die "I haven't considered how to upscale with cuts."
    # Note: cuts were added before splitting and are based on input path. I have to rethink how this works with splitting.
    [ "$SPLIT" = true ] && die "Can't use cuts with splits until I rewrite this!"
    concat_cache_file="$CACHEDIR/concat/$input_rel_path"
    FILTERCMD=("$script_dir/filter.sh" "$input_abs_path" -c "$concat_cache_file")
    EXTRAS=()
    [ "$INTERLACED" = "interlaced" ] && EXTRAS+=("bwdif=mode=1")
    [ "$CROPPING" = none ] || EXTRAS+=("crop=$CROPPING")
    [ "${#EXTRAS[@]}" -gt 0 ] && FILTERCMD+=(-v "$(IFS=,; printf "%s" "${EXTRAS[*]}")")
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
    [ "$INTERLACED" = interlaced ] && VFILTERS+=("bwdif=mode=1")
    [ "$CROPPING" = none ] || VFILTERS+=("crop=$CROPPING")
    # Upscale *after* deinterlacing, per Claude!
    [ -z "$upscale_filters" ] || VFILTERS+=("$upscale_filters")
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
    read -ra ALLOUTS <<<"$OUTSTRING"
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
    done <<<"$stream_data"
#    	NMAPS="${#CUT_STREAMS[@]}"
#    	NMAPS=$((NMAPS-1))
#    	for I in $(seq 0 $NMAPS); do
#    	    MAPS="$MAPS -map ${ALLOUTS[$I]}"
#    	done
  else
    debug "no complex filter; mapping that way"
    # Let KEEP_STREAMS=all mean map every stream. With ffmpeg and one input, a "-map 0" will do that.
    if [ "$KEEP_STREAMS" = all ]; then
      # When a rip has a weird stream that's not really a stream, it seems to break ffmpeg's time and speed estimates.
      # only include true video, audio, and subtitle (if present) streams.
      MAPS="-map 0:V -map 0:a -map 0:s?"
    else
      for S in "${KEEP_STREAMS[@]}"; do
        MAPS="$MAPS -map $S"
      done
    fi
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

  # Second loop to actually process the discovered outputs. This builds the output part of the ffmpeg command by putting
  # together everything we've gathered so far, like the video filters, the one or more output files, any extra ffmpeg
  # options, etc.
  for i in "${!output_abs_paths[@]}"; do
    debug "Output $i"
    output_tmp_path="${output_tmp_paths[i]}"
    output_abs_path="${output_abs_paths[i]}"
    done_file="${done_files[i]}"
    echo "Processing $input_rel_path into $output_abs_path" >&2
    # On the first output, naturally start from the beginning of the input. On subsequent outputs, start from the split
    # time.
    if [ "$i" -gt 0 ]; then
      output_args+=(-ss "${split_times[i]}")
      next="${split_times[i+1]}"
    fi
    # Likewise, include the "to" time on all but the last output, allowing encoding to naturally end at the end of the
    # input.
    if [ "$i" -lt "${#output_abs_paths[@]}" ]; then
      to_time="${split_times[i+1]}"
      if [ -n "$to_time" ]; then
        output_args+=(-to "$to_time")
      fi
    fi
    # This because several videos end up failing with the "Too many packets buffered for output stream XXX" error.
    # I don't think this will cause any problems.
    output_args+=(-max_muxing_queue_size 1024)
    # Use one filter or the other, if set. Setting both will cause an error, but that's checked earlier, and even if it's not,
    # ffmpeg will tell you what you did wrong.
    [ -z "$COMPLEXFILTER" ] || output_args+=(-filter_complex "$COMPLEXFILTER")
    read -ra maps_array <<<"$MAPS"
    output_args+=("${maps_array[@]}" -c copy)
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
        output_args+=(-c:0 "$encoder" "${encoder_settings[@]}" -crf:0 "$VQ")
      fi
    fi
    if [ "$QUALITY" != "rough" ] && [ -n "$TRANSCODE_AUDIO" ]; then
      output_args+=(-c:1 ac3 -ac:1 6 -b:1 384k)
    fi
    # If cutting is happening, encodings to apply will have been calculated previously. You can't do any stream copies
    # when using a complex filtergraph, so every stream needs an encoding.
    [ -n "$COMPLEXFILTER" ] && {
      output_args+=("${encodings[@]}")
    }
    output_args+=(-metadata:s:0 "encoded_by=My smart encoder script")
    if [ "$QUALITY" != "rough" ] && [ -n "$TRANSCODE_AUDIO" ]; then
      output_args+=(-metadata:s:1 "title=Transcoded Surround for Sonos")
    fi
    # I probably should make this an array. I'd just have to convert a whole lot of configs.
    read -ra extra_opts options_arr <<<"$FFMPEG_EXTRA_OPTIONS"
    output_args+=("${extra_opts[@]}" -f matroska "$output_tmp_path")
    debug "Created outputs for: '$output_tmp_path'"
    debug "  outputs: '${output_args[*]}'"
  done

  # Just to be safe, unset the temp vars that were used above so that we don't confuse them with anything later on.
  unset output_abs_path output_tmp_path formatted_output_rel_path done_file already_done

  trap cleanup EXIT

  # Always display the movie length because I use that to gauge
  # progress when watching the logs.
  input_length=$(ffprobe -v error -select_streams v:0 -show_entries stream_tags=DURATION-eng -of default=noprint_wrappers=1:nokey=1 "$input_abs_path" | cut -d '.' -f 1)
  echo "  duration: $input_length"

  # Use locally installed ffmpeg, or a docker container?
  CMD=(ffmpeg)
  #CMD=(docker run --rm -v "$TOOLSDIR":"$TOOLSDIR" -v "$MOVIESDIR":"$MOVIESDIR" -w "$(pwd)" jrottenberg/ffmpeg -stats)

  # Running in docker lately, I've noticed it seems stuck at two cores max. Gemini suggests ffmpeg itself may be to
  # blame in how it detects available threads. Let's tell it how many to use, just to be safe.
  # Continued: it turns out x265 has a completely separate setting and doesn't obey this. Find it up in the
  # encoder_settings. I'm leaving this just because.
  CMD+=(-threads "$(nproc)")

  [ -n "$USE_GPU" ] && ! [ "$NEVER_GPU" ] && CMD+=(-hwaccel cuda -hwaccel_output_format cuda)
  CMD+=(-hide_banner -y -i "$input_abs_path")

  # If doing cuts, use the concat file to attach cut subtitles from the input file
  if [ -n "$COMPLEXFILTER" ]; then
    CMD+=(-safe 0 -f concat -i "$concat_cache_file")
  fi

  CMD+=("${output_args[@]}")
  LOGFILE="$LOGDIR/$input_rel_path.log"

  echo -n "  "
  for arg in "${CMD[@]}"; do
    echo -n "\"${arg//\"/\\\"}\" "
  done
  echo ""
  echo "  View logs:"
  echo "    tail -f \"$LOGFILE\""
  echo "    tail -F currentlog"

  for path in "${output_abs_paths[@]}"; do
    mkdir -p "$(dirname "$path")"
  done
  mkdir -p "$(dirname "$LOGFILE")"
  if [ -n "$DRYRUN" ]; then
    echo "  -- dry run requested, not running"
  else
    echo "  start: $(date)"
    ln -fs "$LOGFILE" currentlog
    "${CMD[@]}" &> "$LOGFILE"
    encode_result="$?"
    echo "  end  : $(date)"
  fi

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
  # Unlock after marking it done, or someone else may pick it up. Of course, there's still a slight chance of race
  # condition here...
  rm -f "$lock_file"
}
export -f encode_one

handle_input() {
  check_for_stop "$@"
}
export -f handle_input

check_for_stop() {
  if [ -f "$script_dir/stop" ]; then
    echo "Stop signalled, stopping"
    return 1
  else
    filter_input "$@"
  fi
}
export -f check_for_stop

filter_input() {
  input_dir="$1"
  input_path="$2"
  if [ -z "$FILTER_INPUT" ] || echo "$input_path" | grep -Ei "$FILTER_INPUT" &>/dev/null; then
    encode_one "$@"
  else
    debug "Filtered out '$input_path'"
  fi
}
export -f filter_input

[ $# -eq 1 ] && ONE=true
[ "$ONE" = true ] && handle_input_file "$1"
[ -z "$ONE" ] && "$script_dir/ls-inputs.sh" -sz | xargs -0I {} bash -c 'IFS="|" read -ra input_fields <<<"{}"; handle_input "${input_fields[@]}" || exit 255'
