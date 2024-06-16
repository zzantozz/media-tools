#!/bin/bash

# Inspects a makemkv info file to extract details needed for matching a ripped disk to data from
# thediscdb.

. allinone/utils

while getopts ":i:" opt; do
  case "$opt" in
    i)
      input="$OPTARG"
      ;;
    *)
      die "Unrecognized arg: $opt"
      ;;
  esac
done

if ! [ -f "$input" ] || ! grep '^CINFO:' "$input" >/dev/null; then
  die "Input (-i) must point to a makemkv info file."
fi

titles=()

handle_start_title() {
  unset duration size_bytes segments file_name mpls_name
}

handle_end_title() {
  [ -n "$duration" ] || die "Duration not set for this title"
  [ -n "$size_bytes" ] || die "Size not set for this title"
  [ -n "$segments" ] || die "Segments not set for this title"
  [ -n "$file_name" ] || die "File name not set for this title"
  [ -n "$mpls_name" ] || die "File name not set for this title"
  # todo: probably accept cli args to set which details to include here and in what order, but atm
  # i'm not thinking of a simple way to do that...
  title="$duration::$size_bytes::$mpls_name::$segments::$file_name"
  titles+=("$title")
}

handle_tinfo() {
  case "$2" in
    duration)
      duration="$4"
      ;;
    size_bytes)
      size_bytes="$4"
      ;;
    segments)
      segments="$4"
      ;;
    file_name)
      file_name="$4"
      ;;
    mpls_name)
      mpls_name="$4"
      ;;
  esac
}

# Why do i need a temp file here? Elsewhere, I was able to do this with something like -i <(cat ... | grep ... )
tmp_file="$(mktemp)"
trap 'rm -f -- "$tmp_file"' EXIT
cat "$input" | grep -E "^TINFO" >"$tmp_file"
. disk-info-parser.sh -i "$tmp_file"

#. disk-info-parser.sh -i "$input"

for t in "${titles[@]}"; do
  echo "$t"
done

