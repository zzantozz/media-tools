#!/bin/bash

# Writes config files based on data gathered from thediscdb.
# First, you need to generate the title data using discdb-match.sh. It should produce lines
# containing the complete information about titles to configure. Titles without matching
# lines aren't configured in thediscdb. A line looks something like
# 0:10:28::1536602112::00460.mpls::670::Extra::A Touch of Black::The Predator-SEG_TouchBlack_t77.mkv

. allinone/utils

while getopts ":m:o:d:" opt; do
  case "$opt" in
    m)
      main_name="$OPTARG"
      ;;
    d)
      data_file="$OPTARG"
      ;;
    o)
      output_dir="$OPTARG"
      ;;
    *)
      die "Unrecognized arg: $OPTARG"
      ;;
  esac
done

[ -f "$data_file" ] || die "-d should point to a data file to consume"
[ -n "$output_dir" ] || die "-o should point to an output dir to create"
[ -f "$output_dir" ] && die "Output dir exists and is a file"
if [ -d "$output_dir" ]; then
  read -p "Output dir already exists. Overwrite content? [y/N] " reply
  [ "$reply" = y ] && go=yes
else
  go=yes
fi

if [ "$go" != yes ]; then
  echo "Exiting"
  exit 0
fi

# Don't leave partial config dirs lying around
trap 'if [ $? != 0 ]; then rm -rf "$output_dir"; fi' EXIT

mkdir -p "$output_dir"
while read -r line; do
  title_type="$(echo "$line" | awk -F :: '{print $5}')"
  title_name="$(echo "$line" | awk -F :: '{print $6}')"
  ripped_file="$(echo "$line" | awk -F :: '{print $7}')"
  case "$title_type" in
    MainMovie)
      prefix=""
      main_name="$title_name"
      ;;
    Extra)
      prefix="Featurettes/"
      ;;
    DeletedScene)
      prefix="Deleted Scenes/"
      ;;
    *)
      die "Don't know how to handle title type: $title_type"
      ;;
  esac
  printf 'OUTPUTNAME="%s%s"\nKEEP_STREAMS=all\n' "$prefix" "$title_name.mkv" >"$output_dir/$ripped_file"
done <"$data_file"

[ -n "$main_name" ] || die "No main title found, so can't create main config file; should be detected from input, but you can set one manually with -m"
printf 'MAIN_NAME="%s"\n' "$main_name" >"$output_dir/main"

