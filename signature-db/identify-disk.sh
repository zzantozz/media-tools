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

while getopts "i:h" opt; do
  case "$opt" in
    i)
      input="$OPTARG";
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

handle_start_title() {
  title_count=$((title_count+1))
}

durations=()
names=()
handle_tinfo() {
  if [ "$2" = duration ]; then
    durations[$title_count]="$(duration_to_secs "$4")"
  elif [ "$2" = mpls_name ]; then
    names[$title_count]="$4"
  fi
}

# Simple solution here is to use every title in the query, but that can add a *lot* of joins and where clauses,
# which can be too many for the database and/or use excessive temporary disk space (looking at you, sqlite).
# To simplify things for the db, just query on the N longest titles here, assuming that the longer titles will
# be the most unique. I.e. lots of disks might have a 30-second title, but fewer would have one that's 01:47:32
# in length. This might also make matching work better. Different editions of the same disk could have different
# "supporting" titles, like disk menus, special features, etc., but the longer titles are probably (hopefully)
# more likely to be the same.
title_query_count=1
add_title_to_query() {
  title_index="$1"
  if [ "$title_query_count" = 1 ]; then
    wheres="i$title_query_count.length = ${durations[$title_index]}"
  elif [ "$title_query_count" = 2 ]; then
    joins="info i$title_query_count on i1.disk_id = i$title_query_count.disk_id"
    wheres="$wheres and i$title_query_count.length = ${durations[$title_index]}"
  elif [ "$title_query_count" -lt 10 ]; then
  #else
    joins="$joins, info i$title_query_count on i1.disk_id = i$title_query_count.disk_id"
    wheres="$wheres and i$title_query_count.length = ${durations[$title_index]}"
  fi
  title_query_count=$((title_query_count+1))
}

. "$script_dir"/../disk-info-parser.sh -i "$1"

# Build a query like
# select * from info i1
# join
#   info i2 on i1.disk_id = i2.disk_id
#   ...
#   info iN on i1.disk_id = iN.disk_id
# where 
#  i1.length = <length of title 1>
#  ...
#  iN.length = <length of title N>

[ "$title_count" -gt 1 ] || die "Need more than one title to build a proper query"

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
# Now for the longest titles, create query parts
for title_index in "${longest_titles[@]}"; do
  add_title_to_query "$title_index"
done

query="select i1.disk_id, i1.disk_name from info i1 join $joins where $wheres group by i1.disk_id;"
cmd=(sqlite3 signature-db/signatures.sqlite "$query")
echo "${cmd[@]}"
"${cmd[@]}"

