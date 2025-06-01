#!/bin/bash -e

die() {
  echo "ERROR - $1" >&2
  exit 1
}

debug() {
  if [[ "$DEBUG" =~ validate ]]; then
    echo "$1" >&2
  fi
}

while getopts "i:" opt; do
  case "$opt" in
    i)
      input="$OPTARG"
      ;;
    *)
      die "Usage!"
      ;;
  esac
done

[ -f "$input" ] || die "Input file not found, set it with -i: '$input'"

VALIDS=(
  KEEP_STREAMS
  CUT_STREAMS
  INTERLACED
  OUTPUTNAME
  FRAMERATE
  FFMPEG_EXTRA_OPTIONS
  TRANSCODE_AUDIO
  CROPPING
  SEASON
  EPISODE
  MAIN_TYPE
  SPECIAL_TYPE
  MAIN_NAME
  SPLIT
  SPLIT_START_NUMBER
  SPLIT_CHAPTER_STARTS
  NEVER_GPU
)

while read -r line; do
  key="${line%%=*}"
  debug "Checking key: '$key'"
  [[ "${VALIDS[*]}" =~ $key ]] || [[ "$key" =~ ^# ]] || {
    echo "Invalid key: $key"
    echo "Acceptable keys are:"
    echo -n "  "
    for p in "${VALIDS[@]}"; do
      echo -n "\"$p\" "
    done
    exit 1
  }
done < "$input"

# Now load up the config and inspect the values. There's a "main" config that all other configs inherit from. Usually,
# the main config is in the same dir as the other config files. Older TV configs are nested by season and disk, and the
# main config is in the root, a few levels up from other configs. We should be able to search recursively upward to find
# it. The main config isn't actually required, and a few disks don't use it because they just don't need the inherited
# configuration.
main_config_dir="$(dirname "$input")"
while ! [ -f "$main_config_dir/main" ] && ! [ "$(basename $"$main_config_dir")" = "config" ]; do
  main_config_dir="$(dirname "$main_config_dir")"
done
if ! [ "$(basename $"$main_config_dir")" = "config" ]; then
  main_config="$main_config_dir/main"
fi

if [ -f "$main_config" ]; then
  # shellcheck disable=SC1090
  source "$main_config"
fi
# shellcheck disable=SC1090
source "$input"

[ -n "$MAIN_NAME" ] || die "Doesn't set a MAIN_NAME"

# Check for a valid output name or tv season+episode
is_tv_config=false
if [ -z "$OUTPUTNAME" ]; then
  debug "No OUTPUTNAME, checking for TV config"
  if [ -n "$SEASON" ] && [ -n "$EPISODE" ]; then
    debug "Season and episode are set explicitly; all good"
    is_tv_config=true
  else
    if [[ "$input" =~ [Ss][Ee][Aa][Ss][Oo][Nn]\ [[:digit:]] ]] && [ -n "$EPISODE" ]; then
      debug "Episode is set, and season is in the path; all good"
      is_tv_config=true
    else
      die "No OUTPUTNAME given, and can't find a season and episode for a tv show"
    fi
  fi
fi

# If an output name is given explicitly, make sure it's ok
if [ -n "$OUTPUTNAME" ]; then
  if ! [[ "$OUTPUTNAME" =~ \.mkv$ ]]; then
    die "OUTPUTNAME is set but doesn't end with .mkv"
  fi
  MATCH=false
  PLEXDIRS=("Behind The Scenes" "Deleted Scenes" "Featurettes" "Interviews" "Scenes" "Shorts" "Trailers" "Other")
  for p in "${PLEXDIRS[@]}"; do
    [[ "$OUTPUTNAME" =~ ^$p/ ]] && MATCH=true
  done
  if ! [ "$MATCH" = true ]; then
    # If the output isn't placed in one of the valid plex dirs, then it should be a main movie file or a tv episode
    # in a "Season" dir.
    # Movies will match the MAIN_NAME in the main config
    [ "$OUTPUTNAME" = "$MAIN_NAME.mkv" ] && MATCH=true
    # But, there are some variations allowed, which we can match on. Wrinkle: some titles have parens with the year,
    # like "Dune (2021)", which will break regex matching, so replace the MAIN_NAME with a token we can safely match on.
    safe_output_name="${OUTPUTNAME/$MAIN_NAME/safe_main_name}"
    # First, different movie editions are also acceptable
    [[ "$safe_output_name" =~ safe_main_name\ \{edition-.*\}\.mkv ]] && MATCH=true
    # TV shows could be mapped explicitly to output paths
    if echo "$safe_output_name" | grep -P "Season \\d+/safe_main_name s\\d+e\\d+.mkv" >/dev/null; then
      MATCH=true
    fi
    # Oh, and some files are multiple episodes...
    if echo "$safe_output_name" | grep -P "Season \\d+/safe_main_name s\\d+e\\d+-e\\d+.mkv" >/dev/null; then
      MATCH=true
    fi
    # And then there's my special system for auto-organizing TV special features, since Plex is terrible at it
    if echo "$safe_output_name" | grep -P "Season 0/safe_main_name s00e\\d{6} - .*.mkv" >/dev/null; then
      MATCH=true
    fi
    # Then there's the crazy episode splitting for Chuck...
    if [ "$SPLIT" = true ] && echo "$safe_output_name" | grep -P "Season \\d+/safe_main_name s\\d+e%0\.2d.mkv" >/dev/null; then
      MATCH=true
    fi
  fi
  if ! [ "$MATCH" = true ]; then
    echo "OUTPUTNAME looks wrong: '$OUTPUTNAME'"
    echo "If this is a movie, the OUTPUTNAME should match the MAIN_NAME."
    echo "If it's a TV show, the OUTPUTNAME should put it in a Season directory, named appropriately."
    echo "If you meant it to be in a Plex special dir, those are:"
    echo -n "  "
    for p in "${PLEXDIRS[@]}"; do
      echo -n "\"$p\" "
    done
    echo ""
    exit 1
  fi
fi

# Check other attributes
[ -n "${KEEP_STREAMS[*]}" ] || {
  echo "Doesn't set KEEP_STREAMS"
  exit 1
}
[ "$KEEP_STREAMS" = all ] || [ "${#KEEP_STREAMS[@]}" -gt 1 ] || {
  echo "KEEP_STREAMS should be the string 'all' or an array with more than one thing in it"
  exit 1
}
D="[[:digit:]]"
[ -z "$CROPPING" ] || [ "$CROPPING" = none ] || [[ "$CROPPING" =~ ^$D+:$D+:$D+:$D+ ]] || {
  echo "CROPPING should be set to 'none' or a valid cropping value like 1900:800:10:120"
  exit 1
}
[ -z "$INTERLACED" ] || [ "$INTERLACED" = interlaced ] || [ "$INTERLACED" = progressive ] || {
  die "INTERLACED should be set to either 'interlaced' or 'progressive'; was '$INTERLACED'"
}
