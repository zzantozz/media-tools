#!/bin/bash

# Quick POC to build a sqlite db from all _info files to be able to query for disks
# by track length(s).

script_dir="$(cd "$(dirname "$0")" && pwd)"

die() {
  echo "ERROR: $1" >&2
  exit 1
}

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

handle_cinfo() {
  if [ "$1" = name1 ]; then
    disk_name="$3"
    # Double any single quotes to escape them for the insert
    disk_name="${disk_name//\'/\'\'}"
  fi
}

handle_tinfo() {
  if [ "$2" = duration ]; then
    title_duration="$(duration_to_secs "$4")"
  elif [ "$2" = mpls_name ]; then
    title_file_name="$4"
  fi
}

flush_batch() {
  echo "  inserting batch"
  sqlite3 "$script_dir/signatures.sqlite" "$batch_prefix $batch $batch_suffix" >/dev/null || die "Failed to insert to db"
  batch=""
}

handle_end_title() {
  stmt="insert into info (disk_id, disk_name, file_name, seq, length, source) values ($disk_count, '$disk_name', '$title_file_name', $title_count, $title_duration, '$source');"
  batch="$batch $stmt"
  title_count=$((title_count+1))
  # Not sure what the max arg length is, but I've overrun it before at ~128k
  if [ "${#batch}" -gt 65536 ]; then
    flush_batch
  fi
}

rm -f "$script_dir/signatures.sqlite"
sqlite3 "$script_dir/signatures.sqlite" 'create table info(pk integer primary key autoincrement, disk_id int, disk_name string, file_name string, seq int, length int, source string)'

batch_prefix="PRAGMA synchronous = OFF; PRAGMA journal_mode = MEMORY; PRAGMA busy_timeout=10000; BEGIN TRANSACTION;"
batch_suffix="END TRANSACTION;"
batch=""
disk_count=0

#f='/home/ryan/thediscdb-data/data/series/Lost (2004)/2013-the-complete-collection-blu-ray-region-b/disc14.txt'
#echo " -- $f"
#title_count=0
#. "$script_dir/../disk-info-parser.sh" -i <(cat "$f" | grep -E '^(CINFO:2,|TINFO:[^,]*,(9|16),)') || die "Failed in processing '$f'"
#sqlite3 "$script_dir/signatures.sqlite" "$batch_prefix $batch $batch_suffix" >/dev/null || die "Failed to insert to db"
#disk_count=$((disk_count+1))
#exit 0

IFS=$'\n'
for f in $(find /mnt/d/ripping /mnt/l/ripping /mnt/k/ripping -name _info); do
  echo " -- $f"
  source="${f//\'/\'\'}"
  title_count=0
  # Filter the input file to speed things up - it works fine without filtering, but it's really slow
  . "$script_dir/../disk-info-parser.sh" -i <(cat "$f" | grep -E '^(CINFO:2,|TINFO:[^,]*,(9|16),)') || die "Failed in processing '$f'"
  disk_count=$((disk_count+1))
  #break
done
for f in $(find /mnt/k/thediscdb-data/ -name '*.txt' -not -name '*-summary.txt'); do
  echo " -- $f"
  source="${f//\'/\'\'}"
  title_count=0
  . "$script_dir/../disk-info-parser.sh" -i <(cat "$f" | grep -E '^(CINFO:2,|TINFO:[^,]*,(9|16),)') || die "Failed in processing '$f'"
  disk_count=$((disk_count+1))
  #break
done
# Make sure to flush anything left to the db
if [ -n "$batch" ]; then
  flush_batch
fi
