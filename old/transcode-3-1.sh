[ -z "$1" ] && {
  echo "First arg input file"
  exit 1
}
[ -z "$2" ] && {
  echo "Second arg output file"
  exit 1
}
IN="$1"
OUT="$2"

ffmpeg -n -i "$IN" -map 0:0 -map 0:1 -map 0:2 -map 0:1 -map 0:3 -c copy -c:a:2 aac -ac:a:2 2 -strict -2 "$OUT"
