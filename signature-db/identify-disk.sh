#!/bin/bash

# Reads output of 'makemkvcon -r info' and uses the title info to match the disk
# the signature database.

script_dir="$(cd "$(dirname "$0")" && pwd)"

usage() {
  cat <<EOF
Usage: $0 [-h] [-i <input file>]

Parses output of 'makemkvcon -r info' to collect details of the titles in it
and matches what it finds against the signature database.

Provide an input file with '-i' or on stdin.
EOF
  exit 1
}

while getopts "i:loh" opt; do
  case "$opt" in
    i)
      input="$OPTARG";
      ;;
    l)
      include_local=true
      ;;
    h|*)
      usage
      ;;
  esac
done

die() {
  echo "ERROR: $1" >&2
  exit 1
}

# Duplicated in ingest.sh - move to common script?
duration_to_secs() {
  unset IFS
  chunks=($(echo "$1" | tr : " "))
  n="${#chunks[@]}"
  if [ "$n" = 1 ]; then
    hours=0; minutes=0; seconds="${chunks[0]}"
  elif [ "$n" = 2 ]; then
    hours=0; minutes="${chunks[0]}"; seconds="${chunks[1]}"
  elif [ "$n" = 3 ]; then
    hours="${chunks[0]}"; minutes="${chunks[1]}"; seconds="${chunks[2]}"
  else
    echo "ERROR: Can't handle a duration with more than three parts: $1"
  fi
  hours="10#$hours"; minutes="10#$minutes"; seconds="10#$seconds"
  echo "$((hours*3600 + minutes*60 + seconds))";
}

##
# Set the initial var values for data that's going to be collected by parsing the makemkv data. Since this script works by invoking
# the data-parsing script and with callback functions, these variables accumulate data across multiple invocations of the functions
# and serve to maintain state between invocations.
#

# This keeps track of which title we're currently looking at. It's incremented each time a new title is seen, so the first title is 1.
title_count=0
# These arrays hold the duration and name of each title encountered, in the order they were seen. This means they're related positionally.
# I.e. for title number 5 (the 5th title seen), durations[5] is its duration, and names[5] is its name.
durations=()
names=()

handle_start_title() {
  title_count=$((title_count+1))
}

handle_tinfo() {
  if [ "$2" = duration ]; then
    durations[$title_count]="$(duration_to_secs "$4")"
  elif [ "$2" = mpls_name ]; then
    names[$title_count]="$4"
  fi
}

# Invoke the parser to grab disk info and populate the variables declared earlier.
. "$script_dir"/../disk-info-parser.sh -i "$1"

# At the moment, this doesn't build a valid query if there was only one title.
[ "$title_count" -gt 1 ] || die "Need more than one title to build a proper query - $1"

# With the data thus gathered, build a query like
# select * from info i1
# join
#   info i2 on i1.disk_id = i2.disk_id
#   ...
#   info iN on i1.disk_id = iN.disk_id
# where 
#  i1.length = <length of title 1>
#  ...
#  iN.length = <length of title N>
#
# Simple solution here is to use every title in the query, but that can add a *lot* of joins and where clauses,
# which can be too many for the database and/or use excessive temporary disk space (looking at you, sqlite).
# To simplify things for the db, just query on the N longest titles here, assuming that the longer titles will
# be the most unique. I.e. lots of disks might have a 30-second title, but fewer would have one that's 01:47:32
# in length. This might also make matching work better. Different editions of the same disk could have different
# "supporting" titles, like disk menus, special features, etc., but the longer titles are probably (hopefully)
# more likely to be the same.

# Find the longest N titles. This does some string foo to sort by the length and keep the indexes of the longest
# ones in a new array. It removes duplicate lengths to further try to match better - I think it's likely that
# some disks might have multiple copies of a main title that others don't.
longest_titles=($(for i in $(seq 1 $title_count); do
  echo "${durations[i]} $i"
done | sort -nruk 1 | head -10 | sed -E 's/.* (.*)/\1/'))

# Now, only for the longest titles, create query parts - the join and where clauses.
title_query_count=1
joins=""
wheres=""
for title_index in "${longest_titles[@]}"; do
  if [ "$title_query_count" = 1 ]; then
    wheres="i$title_query_count.length = ${durations[$title_index]}"
  elif [ "$title_query_count" = 2 ]; then
    joins="info i$title_query_count on i1.disk_id = i$title_query_count.disk_id"
    wheres="$wheres and i$title_query_count.length = ${durations[$title_index]}"
  elif [ "$title_query_count" -lt 10 ]; then
    joins="$joins, info i$title_query_count on i1.disk_id = i$title_query_count.disk_id"
    wheres="$wheres and i$title_query_count.length = ${durations[$title_index]}"
  fi
  title_query_count=$((title_query_count+1))
done

# Now we have all the pieces to build and execute the query.
query="select i1.disk_id, i1.disk_name, i1.source from info i1 join $joins where $wheres"
# For testing, I included my local ripped files in the db. Right now, I mostly only want to query
# for thediscdb data, so by default, don't include the local data.
if ! [ "$include_local" = true ]; then
  for drive in d l k j; do
    query="$query and lower(i1.source) not like '/mnt/$drive/ripping/%'"
  done
fi
query="$query group by i1.disk_id;"
cmd=(sqlite3 signature-db/signatures.sqlite "$query")
IFS=$'\n'
results=($("${cmd[@]}"))

num_matches="${#results[@]}"
[ "$num_matches" -eq 1 ] || die "Matched $num_matches titles, don't know how to proceed"
result="${results[0]}"
disk_id="$(echo "$result" | cut -d '|' -f 1)"
main_title="$(echo "$result" | cut -d '|' -f 2)"
discdb_info_path="$(echo "$result" | cut -d '|' -f 3)"

candidate_query_result="$(sqlite3 signature-db/signatures.sqlite "select length from info where disk_id=$disk_id order by seq")"
candidate_sig="$(echo "$candidate_query_result" | tr '\n' ' ')"
# It's obvious why the db query reults needs newlines translated to something else. I'm not quite sure why this needs it, but testing indicates it does.
# Of course, I could leave the newlines in both, and they'd match fine, but for debugging, it's way more useful to have the title lengths on a single line.
sig_to_match="$(echo ${durations[*]} | tr '\n' ' ')"

# TODO: could "signature" be loosened to a sorted list of title lengths, so that if the same titles appear on two disks in any order, it's a match? not sure about this
if [ "$candidate_sig" = "$sig_to_match" ]; then
  discdb_release_path="$(dirname "$discdb_info_path")"
  discdb_mediaitem_path="$(dirname "$discdb_release_path")"
  title_slug="$(cat "$discdb_mediaitem_path/metadata.json" | jq -r .Slug)"
  release_slug="$(cat "$discdb_release_path/release.json" | jq -r .Slug)"
  disk_basename="$(basename "$discdb_info_path")"
  disk_basename_noext="${disk_basename%.*}"
  disk_index="$(cat "$discdb_release_path/$disk_basename_noext.json" | jq -r .Index)"
  printf "%s::%s::%s\n" "$title_slug" "$release_slug" "$disk_index"
else
  # TODO: add some kind of "number of titles" comparison here. i had an old Aladdin dvd with two titles match the diamond edition bluray that has tons of titles. It's not
  # wrong, exactly, but the titles on the lesser disk could match the wrong things on the greater disk.
  echo "   - Match is close, but full title match failed!"
  echo "     It's likely you have some version of a disk that's in the database but the exact disk version hasn't been recorded yet."
  echo "     You can probably safely use this match and get the main details of the disk right."
  echo "     If you want 100% accuracy, then see <instructions> to add your disk to the database!"
  echo "     Full candidate sig   : $candidate_sig"
  echo "     Current disk to match: $sig_to_match"
fi
