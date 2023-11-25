#!/bin/bash

# Makes it easy to create configs for a new disk of a tv show.

config_dir="/home/ryan/media-tools/allinone/data/config"
base_ripping_dir="/mnt/l/ripping"

die() {
  echo "ERROR: $1" >&2
  exit 1
}

usage() {
  cat <<EOF >&2
Usage: $0 -i <input name> -n <show name> [-s <season number>] [-d <disk number>] [-c <config dir>]

For each ripped files in <input name>, this script displays stream info about the title, and prompts you for
information about it. Based on the info you provide, it writes an appropriate config file into data/config.
The config file will see that the title is written out to the tv-shows output directory with the appropriate
season and episode.

Critical info:

  - episode number: The episode must be provided by you in response to prompts.

  - season number: The season can be detected from the input path if it contains "Season *", or else you 
    can set the season with the '-s' flag.

  - disk number: For special features, the disk number is also required. This can be detected from the
    input path if it contains "Dis[ck] *", or else you can set it with the '-d' flag.

  - show name: This is a required input argument and will be the base directory where the entire show is
    written to.

  - base ripping directory: This is necessary to figure out what kind of input paths we're dealing with.
    At the moment, this is hard-coded.

TV special handling:

This script distinguishes between "special episodes" and "special features". A special episode is something
that shows up in TVDB and so can be mapped to an episode of season 0. A special feature is something that
doesn't show up in TVDB.

  - special episodes: Select this type and enter the episode number from TVDB that this matches.

  - special features: Select this type and enter a descriptive name. I suggest following the pattern
    '<special type> - <special name>' where "special type" matches the available Plex movie specials. This
    allows for migration to a movie special if you want. See below. The script does its best to ensure each
    special feature gets a unique episode number, since Plex will combine specials with the same episode
    number.

TV specials as a movie:

Since Plex is pretty terrible at handling TV specials, unless they're specifically represented in TVDB,
this script supports writing TV specials out as a movie, which works pretty well as far as browsing them in
the Plex UI. Just set this environment variable to do so:

  - TV_SPECIALS_AS_MOVIE: tells this script to write "special features" to the movies dir instead of the tv-shows
    dir. This actually gives a better overall experience for browsing TV specials, since you can see their names.
    Note that you have to have a root "movie file" in order for it to show up in the Plex movies library.
EOF
  exit 1
}

while getopts "i:n:c:s:d:" opt; do
  case "$opt" in
    i)
      input_name="$OPTARG"
      ;;
    n)
      show_name="$OPTARG"
      ;;
    s)
      season="$OPTARG"
      ;;
    d)
      disk="$OPTARG"
      ;;
    c)
      config_dir="$OPTARG"
      ;;
  esac
done

if [ -z "$input_name" ] || [ -z "$show_name" ]; then
  usage
fi

if [ -d "$input_name" ]; then
  input_dir="$input_name"
fi

if ! ([ -d "$config_dir" ] && [ "config" = "$(basename "$config_dir")" ] && [ "data" = "$(basename "$(dirname "$config_dir")")" ]); then
  die "config dir should point at a config dir in the media toolset, was: $config_dir"
fi

# Expect tv show structure and parse some info from it. Season and disk is usually numeric. Exceptions: season can be like "3.5" (BSG).
# Disks can be like "1A" and "1B" (House).
echo "input dir: $input_dir"
[ -z "$season" ] && [[ "$input_dir" =~ Season\ ([0-9\.]+) ]] && season="${BASH_REMATCH[1]}"
[[ "$input_dir" =~ Dis[ck]\ ([0-9A-Z]+) ]] && disk="${BASH_REMATCH[1]}"
rel_path="${input_dir//$base_ripping_dir\/}"
base_input_name="${rel_path%%/*}"
[ -n "$season" ] || die "Didn't get a season number, and couldn't parse one from the input path"
[ -n "$disk" ] || die "Didn't get a disk number, and couldn't parse one from the input path"
echo "Discovered from input: rel_path name='$rel_path' base_input_name='$base_input_name' season='$season' disk='$disk'"

# Figure out where to put the configs
main_config_dir="$config_dir/$base_input_name"
main_config="$main_config_dir/main"
echo -e "configs:\n  show: $main_config_dir\n  main: $main_config"

# Ensure main file exists with correct content
mkdir -p "$main_config_dir"
if [ -f "$main_config" ]; then
  grep "MAIN_NAME=\"$show_name\"" "$main_config" || die "Show name mismatch. Expected $show_name, but main has $(cat "$main_config")"
else
  echo "MAIN_NAME=\"$show_name\"" > "$main_config"
fi

probe() {
  PROBE_RESULT="$(ffprobe -probesize 42M -i "$1" 2>&1 | grep Stream)"
}

special_counter=0
for f in "$input_dir"/*; do
  echo ""
  echo "Details of $f"
  echo ""
  probe "$f"
  echo "$PROBE_RESULT"
  echo ""
  echo "What is this?"
  select t in "Episode" "Special Episode" "Special Feature" "skip it"; do
    if [ "$t" = "skip it" ]; then
      break
    fi
    disk_number="$(printf %0.2d "$disk")"
    season_number="$(printf %0.2d "$season")"
    if [ "$t" = "Episode" ]; then
      read -p "Enter episode number: " answer
      episode_number="$(printf %0.2d "$answer")"
      out_name="Season $season_number/$show_name s${season_number}e${episode_number}.mkv"
    elif [ "$t" = "Special Episode" ]; then
      read -p "Enter episode number: " answer
      episode_number="$(printf %0.2d "$answer")"
      out_name="Season 0/$show_name s00e${episode_number}.mkv"
    elif [ "$t" = "Special Feature" ]; then
      read -p "Name: " answer
      if [ -n "$TV_SPECIALS_AS_MOVIE" ]; then
        echo "Write this!"
        exit 1
      else
        # Make up an "episode" number that'll be unique. Plex only goes by the episode number, not the name. If you make two specials with the same episode, it
        # considers them two versions of the same thing.
        id="$(printf '%0.2d%0.2d%0.2d' $season $disk $special_counter)"
        out_name="Season 0/$show_name s00e${id} - $answer.mkv"
        special_counter=$((special_counter+1))
      fi
    else
      echo "Not yet written"
      exit 1
    fi
    read -p "Keep (a)ll streams or (s)elect streams? [A/s] " answer
    if [ "$answer" = "" ] || [ "$answer" = a ]; then
      keep_streams=all
    else
      read -p "Enter space-separated streams to keep: " -a answer
      keep_streams=()
      for s in "${answer[@]}"; do
        keep_streams+=("0:$s")
      done
      keep_streams="(${keep_streams[@]})"
    fi
    read -p "Encode '$f' as '$out_name' with streams $keep_streams? [Y/n] " answer
    if [ -z "$answer" ] || [ "$answer" = y ]; then
      config_file="$config_dir/$rel_path/$(basename "$f")"
      mkdir -p "$(dirname "$config_file")"
      echo "Writing to $config_file"
      echo "OUTPUTNAME=\"$out_name\"" > "$config_file"
      echo "KEEP_STREAMS=$keep_streams" >> "$config_file"
      read -p "Any extras? [y/N] " answer
      if [ "$answer" = y ]; then
        echo "Enter extra lines to append to config, followed by ^D"
        extras=$(</dev/stdin)
        echo "$extras" >> "$config_file"
      fi
      break
    fi
  done
done

