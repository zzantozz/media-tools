#!/bin/bash

# This is a first stab at getting disk config from thediscdb. It'll assume an exact disk match
# has been found and just match up the titles. Any non-match will cause a failure. Later, I'll
# probably want a different script to handle non-exact matches. It should probably try multiple
# things, like matching things up by duration, checking the mpls names, and maybe looking at
# segment maps.

# Takes in disk info lines as output by disk_match_info.sh, which look like this:
# 0:01:38::340015104::00481.mpls::683,674,682::The Predator-SF_DS_01_t101.mkv
# A line is duration, size, mpls name, segments, and file name delimited by "::".

# Takes in query info with a similar structure. The first four fields are the same
# and are used for matching disk info to query info. The query info should contain
# additional fields carrying the important query information: title type, title name,
# and possibly season and episode information. Maybe more to come?

. allinone/utils

while getopts ":d:q:" opt; do
  case "$opt" in
    d)
      disk_info="$OPTARG"
      ;;
    q)
      query_info="$OPTARG"
      ;;
    *)
      die "Unrecognized arg: $opt"
      ;;
  esac
done

[ -f "$disk_info" ] || die "-d should point at a file containing match info from disk-match-info.sh"
[ -f "$query_info" ] || die "-q should point at discdb query info made to align with the requirements of this script"

while IFS=$'\n' read -r line; do
  match_string="$(echo "$line" | awk -F "::" '{printf "%s::%s::%s::%s::", $1, $2, $3, $4}')"
  if match="$(grep "^$match_string" "$disk_info")"; then
    title_type="$(echo "$line" | awk -F "::" '{print $5}')"
    title_name="$(echo "$line" | awk -F "::" '{print $6}')"
    rip_file_name="$(echo "$match" | awk -F "::" '{print $5}')"
    echo "$line::$rip_file_name"
  else
    die "Disk info didn't have a match for a title mapped in thediscdb: $line"
  fi 
done <"$query_info"
