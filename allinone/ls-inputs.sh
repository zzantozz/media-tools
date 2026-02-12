#!/bin/bash

# How do I centralize this kind of config instead of repeating it everywhere?
# Source a central config file in each script?

script_dir="$(cd "$(dirname "$0")" && pwd)"

source "$script_dir/config"
source "$script_dir/utils"

if [ -n "$INPUT_DIRS" ]; then
  IFS=: read -ra input_dirs <<<"$INPUT_DIRS"
else
  input_dirs=("$input_dir")
fi

for dir in "${input_dirs[@]}"; do
  [ -d "$dir" ] || die "Input dir doesn't exist: '$input_dir'"
done

usage() {
  echo "USAGE"
  echo "    INPUT_DIRS=/a:/b:/c $0 [-s|-S] [-r] [-z]"
  echo
  echo "DESCRIPTION"
  echo "    Finds video files in input directories and writes them to stdout in a format understandable by encode.sh."
  echo
  echo "OPTIONS"
  echo "    INPUT_DIRS"
  echo "        A list of input directories to scan for transcodable video files. Separated by colons."
  echo
  echo "    -s"
  echo "        Sort naturally, meaning by name."
  echo
  echo "    -S"
  echo "        Sort by size."
  echo
  echo "    -r"
  echo "        Reverse the list after sorting."
  echo
  echo "    -z"
  echo "        Delimit results with nul instead of a newline."
}

sort=none
reverse=false
zero=false

while getopts ":sSrz" opt; do
  case "$opt" in
    s)
      sort=natural
      ;;
    S)
      sort=size
      ;;
    r)
      reverse=true
      ;;
    z)
      zero=true
      ;;
    *)
      usage
      exit 1
  esac
done

if [ "$reverse" = true ] && [ "$sort" = none ]; then
  die "Can't reverse if not sorting!"
fi

find_cmd=(find "${input_dirs[@]}" -name '*.mkv' -mmin +2 -printf)
printf_format=""
sort_cmd=()
cleanup_cmd=()

if [ "$sort" = size ]; then
  printf_format+='%s %H|%P'
  sort_cmd=(sort -n)
  cleanup_cmd=(cut -d ' ' -f 2-)
elif [ "$sort" = natural ]; then
  printf_format+='%H|%P'
  sort_cmd=(sort -k 2 -t '|')
else
  printf_format+='%H|%P'
fi

if [ "$reverse" = true ]; then
  sort_cmd+=(-r)
fi

if [ "$zero" = true ]; then
  printf_format+='\0'
else
  printf_format+='\n'
fi

find_cmd+=("$printf_format")

_find() {
  "${find_cmd[@]}"
}

_sort() {
  if [ -n "${sort_cmd[*]}" ]; then
    "${sort_cmd[@]}"
  else
    cat -
  fi
}

_cleanup() {
  if [ -n "${cleanup_cmd[*]}" ]; then
    "${cleanup_cmd[@]}"
  else
    cat -
  fi
}

_find | _sort | _cleanup

exit 0

# Everything below is other ways I came up with of dealing with this.
# I think the above is the best solution.

"${find_cmd[@]}" | if [ -n "$sort_cmd" ]; then
  "${sort_cmd[@]}"
else
  cat -
fi | if [ -n "$cleanup_cmd" ]; then
  "${cleanup_cmd[@]}"
else
  cat -
fi | if [ -n "$zero_cmd" ]; then
  "${zero_cmd[@]}"
else
  cat -
fi

exit 0

case "$sort:$reverse:$zero" in
  none:*:false)
    find "$input_dir" -name '*.mkv' -mmin +2
    ;;
  none:*:true)
    find "$input_dir" -name '*.mkv' -mmin +2 | tr '\n' '\0'
    ;;
  natural:false:false)
    find "$input_dir" -name '*.mkv' -mmin +2 | sort
    ;;
  natural:true:false)
    find "$input_dir" -name '*.mkv' -mmin +2 | sort -r
    ;;
  natural:false:true)
    find "$input_dir" -name '*.mkv' -mmin +2 | sort | tr '\n' '\0'
    ;;
  natural:true:true)
    find "$input_dir" -name '*.mkv' -mmin +2 | sort -r | tr '\n' '\0'
    ;;
  size:false:false)
    find "$input_dir" -name '*.mkv' -mmin +2 -exec ls -s {} \; | sort | cut -d ' ' -f 2-
    ;;
  size:true:false)
    find "$input_dir" -name '*.mkv' -mmin +2 -exec ls -s {} \; | sort -r | cut -d ' ' -f 2-
    ;;
  size:false:true)
    find "$input_dir" -name '*.mkv' -mmin +2 -exec ls -s {} \; | sort | tr '\n' '\0' | cut -d ' ' -f 2-
    ;;
  size:true:true)
    find "$input_dir" -name '*.mkv' -mmin +2 -exec ls -s {} \; | sort -r | tr '\n' '\0' | cut -d ' ' -f 2-
    ;;
  *)
    die "Oops, unhandled combination of options!"
    ;;
esac

