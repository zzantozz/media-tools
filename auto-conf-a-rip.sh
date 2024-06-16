#!/bin/bash

script_dir="$(cd "$(dirname "$0")" && pwd)"

. "$script_dir/allinone/utils"

while getopts ":i:" opt; do
  case "$opt" in
    i)
      input_dir="$OPTARG"
      ;;
    *)
      die "Unrecognized arg: $OPTARG"
      ;;
  esac
done

[ -d "$input_dir" ] || die "-i should point to a ripped movie dir"

full_info="$input_dir/_info"
ripped_info="$input_dir/_info_30"

[ -f "$full_info" ] || die "Missing full makemkv info file at '$full_info'"
[ -f "$ripped_info" ] || die "Missing ripped makemkv info file at '$ripped_info'"

trap 'rm -f disk_match_info discdb_info matched_data' EXIT

discdb_info="$(cat "$full_info" | signature-db/identify-disk.sh)" || die "Failed to identify disk"
title_slug="$(echo "$discdb_info" | awk -F :: '{print $1}')"
release_slug="$(echo "$discdb_info" | awk -F :: '{print $2}')"
disk_index="$(echo "$discdb_info" | awk -F :: '{print $3}')"
read -p "Does this look right? title: $title_slug release: $release_slug disk: $disk_index [y/N] " reply
if ! [ "$reply" = y ]; then
  echo "Exiting"
  exit 0
fi

./disk-match-info.sh -i "$input_dir/_info_30" >disk_match_info || die "Failed to build disk info from makemkv file"
./discdb-query.sh -t "$title_slug" -r "$release_slug" -d "$disk_index" | \
  jq -rc '.data.mediaItems.nodes[0].releases[0].discs[0].titles[] | "\(.duration)::\(.size)::\(.sourceFile)::\(.segmentMap)::\(.item.type)::\(.item.title)"' >discdb_info || \
  die "Failed to get disk info from thediscdb"
bash ./discdb-match.sh -d disk_match_info -q discdb_info >matched_data || die "Failed to match local disk data againt thediscdb"
config_dir="$script_dir/allinone/data/config/$(basename "$input_dir")"

echo " *** Summary ***"
cat matched_data | awk -F :: '{printf "%s = %s/%s\n", $7, $5, $6}'
echo
read -p "Write these to $config_dir? [y/N] " reply
if ! [ "$reply" = y ]; then
  echo "Exiting"
  exit 0
fi

./auto-conf-from-discdb.sh -d matched_data -o "$config_dir" || die "Failed to generate config files from combined data"
echo "Wrote configs to $config_dir"
