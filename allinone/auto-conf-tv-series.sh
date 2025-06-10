#!/bin/bash

# A first stab at formalizing an automatic ripping script for complete tv shows. I used minor variations of this to recently generate configs for:
#
# - Walker Texas Ranger
# - The Flintstones
# - Full House
#
# It seems to work quite well. It supports several features that are commonly problems for tv show mapping:
#
# - putting disks in the right order when their labels don't match
# - ignoring non-episode titles by setting file size thresholds
# - handling multi-episode titles, again by setting file size thresholds
# - explicitly ignoring certain titles that fall within the size thresholds but aren't actual episodes
# - for Walker Texas Ranger, but not entirely represented here yet, it even handled a scenario where the dvd "season 1" was actually seasons 1 and 2 according to tmdb

script_dir="$(cd "$(dirname "$0")" && pwd)"
source "$script_dir/utils"
source "$script_dir/config"

unset season; unset episode; unset season_from_path; unset raw_episode;

media_tools_dir="$script_dir/.."
show_name=""
input_dir_matches=()
nomatch_seasons=()
title_ignores=("Something to ignore because it can't be empty")
season_regexes=("Season (.)" "SEASON (.)")
season_regex_group=1
season_strategy=from_path
season_episodes=()

while getopts ":n:i:m:x:r:s:g:t:e:o:d:u:" opt; do
  case "$opt" in
    n)
      show_name="$OPTARG"
      ;;
    i)
      input_dir_matches+=("$OPTARG")
      ;;
    m)
      episode_size_min="$OPTARG"
      ;;
    x)
      episode_size_max="$OPTARG"
      ;;
    r)
      season_regexes+=("$OPTARG")
      ;;
    g)
      season_regex_group="$OPTARG"
      ;;
    s)
      nomatch_seasons+=("$OPTARG")
      ;;
    t)
      season_strategy="$OPTARG"
      ;;
    e)
      [[ "$OPTARG" =~ ^[0-9]+$ ]] || die "Season episode count must be numeric"
      season_episodes+=("$OPTARG")
      ;;
    o)
      title_ignores+=("$OPTARG")
      ;;
    d)
      duration_min="$OPTARG"
      ;;
    u)
      duration_max="$OPTARG"
      ;;
    *)
      echo "Unrecognized arg: $opt"
      exit 1
      ;;
  esac
done

[ -n "$show_name" ] || die "Show name is required (use -n)"
[ "${#input_dir_matches[@]}" -gt 0 ] || die "At least one input dir match is required. (use -i with 'find -path ...' matching)"
[ -d "$input_dir" ] || die "Input dir doesn't exist: $input_dir (override with INPUTDIR env)"
[[ "$season_regex_group" =~ ^[0-9]+$ ]] || die "Regex group must be numeric"
if [ -n "$episode_size_min" ] || [ -n "$episode_size_max" ]; then
  if [ -n "$duration_min" ] || [ -n "$duration_max" ]; then
    die "Can only set size or duration min/max"
  fi
fi

last_season=0
declare -A nomatch_season_cache
nomatch_season_counter=0
total_episodes_seen=0

while read -r line; do
  unset season_from_path num_sodes season episode episode_spec output_name rel_path main_file
  size="$(echo "$line" | cut -d " " -f 1)"
  # Handle path carefully - could have multiple whitespaces, which cut and awk will remove
  path="$(echo "$line" | sed -r 's/^\S+\s+//')"
  if [ -n "$episode_size_min" ] || [ -n "$episode_size_max" ]; then
    if [ "$size" -lt $episode_size_min ]; then num_sodes=0; elif [ "$size" -lt $episode_size_max ]; then num_sodes=1; else num_sodes=2; fi
  fi
  if [ -n "$duration_min" ] || [ -n "$duration_max" ]; then
    duration=$(ffprobe -v error -select_streams v:0 -show_entries stream_tags=DURATION-eng -of default=noprint_wrappers=1:nokey=1 "$path" | cut -d '.' -f 1)
    secs="$(duration_to_secs "$duration")"
    [ -n "$duration_min" ] && duration_min_secs="$(duration_to_secs "$duration_min")"
    [ -n "$duration_max" ] && duration_max_secs="$(duration_to_secs "$duration_max")"
    if [ -n "$duration_min" ] && [ -n "$duration_max" ]; then
      if [ "$secs" -lt "$duration_min_secs" ]; then
        num_sodes=0
      elif [ "$secs" -lt "$duration_max_secs" ]; then
        num_sodes=1
      else
        num_sodes=2
      fi
    elif [ -n "$duration_min" ] && [ "$secs" -lt "$duration_min_secs" ]; then
      num_sodes=0
    elif [ -n "$duration_max" ] && [ "$secs" -gt "$duration_max_secs" ]; then
      num_sodes=2
    else
      num_sodes=1
    fi
  fi
  # In case no min/max of any kind is set...
  [ -n "$num_sodes" ] || num_sodes=1
  if [ "$num_sodes" = 0 ]; then echo "skip $path"; 
  else
    if [ "$season_strategy" = from_path ]; then
      for rex in "${season_regexes[@]}"; do
        if [[ "$path" =~ $rex ]]; then
          season_from_path="${BASH_REMATCH[$season_regex_group]}"
          break;
        fi
      done
      if [ -z "$season_from_path" ]; then
        dir="$(dirname "$path")"
        if [ -n "${nomatch_season_cache[$dir]}" ]; then
          season_from_path="${nomatch_season_cache[$dir]}"
        else
          next_nomatch_season="${nomatch_seasons[$nomatch_season_counter]}"
          [ -n "$next_nomatch_season" ] || die "No season regex match and no 'nomatch season' set for this path: $dir (set season regex with -r)"
          nomatch_season_cache["$dir"]="$next_nomatch_season"
          season_from_path="$next_nomatch_season"
          nomatch_season_counter=$((nomatch_season_counter+1))
        fi
      fi
    elif [ "$season_strategy" = count_episodes ]; then
      local_s=0
      cum_season_episodes="${season_episodes[$local_s]}"
      while [ "$cum_season_episodes" -lt "$((total_episodes_seen+1))" ]; do
        local_s=$((local_s+1))
        this_season_episodes="${season_episodes[$local_s]}"
        cum_season_episodes=$((cum_season_episodes + this_season_episodes))
      done
      season_from_path=$((local_s+1))
    else
      die "Unsupported season strategy: $season_strategy"
    fi
    [ -n "$season_from_path" ] || die "Couldn't determine season"
    if [ $season_from_path != $last_season ]; then raw_episode=1; fi
    season=$season_from_path; episode=$raw_episode
    episode_spec="$(printf "e%02d" "$episode")"
    if [ $num_sodes = 2 ]; then episode_spec="$(printf "e%02d-e%02d" "$episode" "$((episode+1))")"; fi
    output_name="$(printf "Season $season/$show_name s%02d%s.mkv" "$season" "$episode_spec")"
    echo "$path - raw_s$season_from_path raw_e$raw_episode sodes=$num_sodes s$season e$episode - $output_name"
    rel_path="${path/$input_dir/}"; config_path="$media_tools_dir/allinone/data/config/$rel_path"; echo "  -> $config_path"
    main_file="$media_tools_dir/allinone/data/config/$(dirname "$rel_path")/main"
    if [ "$DRYRUN" = false ]; then
      mkdir -p "$(dirname "$config_path")"
      echo "MAIN_NAME='$show_name'" >"$main_file"
      echo -e "OUTPUTNAME='$output_name'\nKEEP_STREAMS=all" >"$config_path"
    fi
    raw_episode=$((raw_episode+num_sodes))
    total_episodes_seen=$((total_episodes_seen+num_sodes))
    last_season="$season_from_path"
  fi
done <<<"$( (
  ignore_string=XXXXXXXXXXXXXXXXX
  for ignore in "${title_ignores[@]}"; do
    ignore_string="$ignore|$ignore_string"
  done
  for input_dir_match in "${input_dir_matches[@]}"; do
    find "$input_dir" -path "$input_dir_match" -type f -name "*.mkv" | grep -Ev "($ignore_string)" | sort
  done
  ) | xargs -I {} ls -s "{}"
)"
