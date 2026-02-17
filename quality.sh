#!/bin/bash -e

script_dir="$(cd "$(dirname "$0")" && pwd)"

source "$script_dir/allinone/config"

[ $# -eq 1 ] || {
	echo "Pass the name of a video file to determine what quality to encode with."
	echo "Prints the x.265 CRF factor that should be used."
	exit 1
}

DATA=$(ffprobe -i "$1" 2>&1 | grep "Stream #0:0") || die "Failed to run ffprobe"

if [[ "$DEBUG" =~ quality ]]; then
  echo "ffprobe output:" >&2
  echo "$DATA" >&2
fi

[[ $DATA =~ 720x480 ]] && Q=22
[[ $DATA =~ 1280x720 ]] && Q=22
[[ $DATA =~ 1918x1080 ]] && Q=20
[[ $DATA =~ 1920x1080 ]] && Q=20
[[ $DATA =~ 3840x2160 ]] && Q=20
[ -z "$Q" ] && {
  die "Can't figure out what video quality to use. Data found was: '$DATA'"
}
echo $Q
