#!/bin/bash

set -e

echo "My video transcode helper. Every cli option has a corresponding uppercase env var."

[ -n "$CONFIG" ] && . "$CONFIG"

[ -z "$INPUT" ] && {
	[ -f "$1" ] || {
		echo "First arg should be the video to encode or set INPUT var."
		exit 1
	}
	INPUT="$1"
	shift
}

echo ''
echo '  *** Stream helper'
ffprobe -i "$INPUT" 2>&1 | grep Stream
echo ''
echo ''

[ -z "$OUTPUT" ] && {
	[ "$1" = "output" -a -n "$2" ] || {
		echo "After input, supply 'output <dest>' for output file."
		exit 1
	}
	OUTPUT="$2"
	shift 2
}

[ -z "$VQ" ] && {
	[ "$1" = "vq" -a -n "$2" ] || {
		echo "After output, supply 'vq <quality>' for video quality, where <quality> is the libx265 -crf factor."
		exit 1
	}
	VQ=$2
	shift 2
}

[ -z "$AS" ] && {
	[ "$1" = "as" -a -n "$2" ] || {
		echo "After video quality, supply 'as <number>' to indicate the main audio stream."
		exit 1
	}
	AS=$2
	shift 2
}

[ -z "$AS_TRANSCODE" ] && {
	[ "$1" = "as_transcode" -a -n "$2" ] || {
		echo "After audio stream, supply 'as_transcode [true|false]' to indicate whether to transcode selected stream for Sonos compatibility."
		exit 1
	}
	AS_TRANSCODE=$2
	shift 2
}

[ -z "$COPIES" ] && {
	[ "$1" = "copies" -a -n "$2" ] || {
		echo "After as_transcode, supply 'copies <s1>,<s2>,...,<sN>', listing streams to copy, not including stream 0, assumed to be the video stream."
		exit 1
	}
	COPIES=$2
	shift 2
}
IFS=',' read -r -a COPIES_ARR <<< "$COPIES"

[ "$1" = "justgo" ] && {
	JUSTGO=true
	shift
}

echo "Encode: $INPUT"
echo "  output: $OUTPUT"
echo "  video quality $VQ"
echo "  main audio stream #0:$AS"
[ "$AS_TRANSCODE" = "true" ] && {
	echo "    transcode for Sonos"
}
echo "  copy streams [${COPIES_ARR[@]}]"
echo "  additional options (just append to command line or set EXTRA_OPTIONS): $EXTRA_OPTIONS $@"
echo ""
echo "Encoding command:"
CMD=(ffmpeg -y -i "$INPUT" -map 0:0 -map 0:$AS)
for S in "${COPIES_ARR[@]}"; do
	CMD+=(-map 0:$S)
done
CMD+=(-c copy -c:0 libx265 -crf "$VQ")
[ "$AS_TRANSCODE" = "true" ] && {
	CMD+=(-c:1 ac3 -ac:1 6 -b:1 640k -metadata:s:1 title="Transcoded Surround for Sonos" -disposition:a:1 0)
}
CMD+=(-metadata:s:0 encoded_by="My personal encoder script")
CMD+=($EXTRA_OPTIONS $@ "$OUTPUT")
echo -n "ffmpeg "
for arg in "${CMD[@]:1}"; do
	echo -n "\"${arg//\"/\\\"}\" "
done
echo ""

[ "$JUSTGO" = "true" ] || {
	read -p "Go ahead with encode? (Use 'justgo' after copies to suppress this.) " REPLY
	[ "$REPLY" = 'y' ] || {
		exit 1
	}
}
echo "going!"
"${CMD[@]}" 2>&1

cat <<EOF > last-encode-config
INPUT="$INPUT"
OUTPUT="$OUTPUT"
VQ="$VQ"
AS="$AS"
AS_TRANSCODE="$AS_TRANSCODE"
COPIES="$COPIES"
EXTRA_OPTIONS="$EXTRA_OPTIONS $@"
EOF

echo ""
echo "Settings for this encode written to file last-encode-config."

