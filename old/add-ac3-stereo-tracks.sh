#!/bin/bash -e

[ "$1" = "" ] && {
  echo "First arg should be path to movie file to add AC3 audio tracks to."
  exit 1
}

IN="$1"
OUT="/mnt/x/ripping/ac3-add-$(basename "$IN")"
CMD="ffmpeg -i \"$IN\" -codec copy"
IFS=$'\n'
LINES=`ffprobe -v quiet -show_streams -i "$IN" | grep --regexp codec_name --regexp index`
OUT_INDEX=0
for L in $LINES; do
  [[ $L =~ "index" ]] && IN_INDEX=${L:6}
  [[ $L =~ "codec_name" ]] && {
    CODEC=${L:11}
    CMD="$CMD -map 0:$IN_INDEX"
    [ $CODEC = "dts" ] && {
      OUT_INDEX=$((OUT_INDEX+1))
      CMD="$CMD -map 0:$IN_INDEX -codec:$OUT_INDEX ac3 -filter:$OUT_INDEX \"pan=stereo|FL=FC+0.30*FL+0.30*BL|FR=FC+0.30*FR+0.30*BR\""
    }
    OUT_INDEX=$((OUT_INDEX+1))
  }
done
CMD="$CMD \"$OUT\""
eval "$CMD"
