#!/bin/bash

# How do I centralize this kind of config instead of repeating it everywhere?
# Source a central config file in each script?

script_dir="$(cd "$(dirname "$0")" && pwd)"

source "$script_dir/config"
source "$script_dir/utils"

[ -d "$input_dir" ] || die "Input dir doesn't exist: '$input_dir'"

usage() {
  echo "Learn how to use it."
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

find_cmd=(find "$input_dir" -name '*.mkv' -mmin +2)
sort_cmd=()
cleanup_cmd=()
zero_cmd=()

if [ "$sort" = size ]; then
  find_cmd+=(-exec ls -s {} \;)
  sort_cmd=(sort -n)
  cleanup_cmd=(cut -d ' ' -f 2-)
elif [ "$sort" = natural ]; then
  sort_cmd=(sort)
fi

if [ "$reverse" = true ]; then
  sort_cmd+=(-r)
fi

if [ "$zero" = true ]; then
  zero_cmd=(tr '\n' '\0')
fi

_find() {
  "${find_cmd[@]}"
}

_sort() {
  if [ -n "$sort_cmd" ]; then
    "${sort_cmd[@]}"
  else
    cat -
  fi
}

_cleanup() {
  if [ -n "$cleanup_cmd" ]; then
    "${cleanup_cmd[@]}"
  else
    cat -
  fi
}

_zero() {
  if [ -n "$zero_cmd" ]; then
    "${zero_cmd[@]}"
  else
    cat -
  fi
}

_find | _sort | _cleanup | _zero

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

