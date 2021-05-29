#!/bin/bash -e

[ $# -eq 1 ] || {
	echo "Pass the name of a file to ffprobe and tell if it fits a known profile."
	exit 1
}

DATA=$(ffprobe -analyzeduration 2147483647 -probesize 2147483647 -i "$1" 2>&1 | grep Stream)
LINES=$(echo "$DATA" | wc -l)
[ "$DEBUG" = "profile" ] && echo -e "Data is $LINES lines:\n$DATA"

MATCH=true
[ $LINES -eq 4 ] || MATCH=false
[ "$DEBUG" = "profile" ] && echo $MATCH
[[ $DATA =~ Stream\ #0:0.*(720x480|1280x720) ]] || MATCH=false
[ "$DEBUG" = "profile" ] && echo $MATCH
[[ $DATA =~ Stream\ #0:1.*Audio:\ ac3.*stereo ]] || MATCH=false
[ "$DEBUG" = "profile" ] && echo $MATCH
[[ $DATA =~ Stream\ #0:2.*Subtitle ]] || MATCH=false
[ "$DEBUG" = "profile" ] && echo $MATCH
[[ $DATA =~ Stream\ #0:3:\ Video:\ mjpeg ]] || MATCH=false
[ "$DEBUG" = "profile" ] && echo $MATCH
[ $MATCH = true ] && {
	echo "bsg-1"
	exit 0
}

MATCH=true
[ $LINES -eq 4 ] || MATCH=false
[ "$DEBUG" = "profile" ] && echo $MATCH
[[ $DATA =~ Stream\ #0:0.*(1920x1080) ]] || MATCH=false
[ "$DEBUG" = "profile" ] && echo $MATCH
[[ $DATA =~ Stream\ #0:1.*Audio:\ dts\ \(DTS-HD\ MA\).*5\.1 ]] || MATCH=false
[ "$DEBUG" = "profile" ] && echo $MATCH
[[ $DATA =~ Stream\ #0:2.*Audio:\ dts\ \(DTS\).*5\.1 ]] || MATCH=false
[ "$DEBUG" = "profile" ] && echo $MATCH
[[ $DATA =~ Stream\ #0:3:\ Video:\ mjpeg ]] || MATCH=false
[ "$DEBUG" = "profile" ] && echo $MATCH
[ $MATCH = true ] && {
        echo "bsg-2"
        exit 0
}

MATCH=true
[ $LINES -eq 6 ] || MATCH=false
[ "$DEBUG" = "profile" ] && echo $MATCH
[[ $DATA =~ Stream\ #0:0.*(1920x1080) ]] || MATCH=false
[ "$DEBUG" = "profile" ] && echo $MATCH
[[ $DATA =~ Stream\ #0:1.*Audio:\ dts\ \(DTS-HD\ MA\).*5\.1 ]] || MATCH=false
[ "$DEBUG" = "profile" ] && echo $MATCH
[[ $DATA =~ Stream\ #0:2.*Audio:\ dts\ \(DTS\).*5\.1 ]] || MATCH=false
[ "$DEBUG" = "profile" ] && echo $MATCH
[[ $DATA =~ Stream\ #0:3.*Audio:\ ac3.*stereo ]] || MATCH=false
[ "$DEBUG" = "profile" ] && echo $MATCH
[[ $DATA =~ Stream\ #0:4.*Subtitle:\ hdmv_pgs_subtitle ]] || MATCH=false
[ "$DEBUG" = "profile" ] && echo $MATCH
[[ $DATA =~ Stream\ #0:5:\ Video:\ mjpeg ]] || MATCH=false
[ "$DEBUG" = "profile" ] && echo $MATCH
[ $MATCH = true ] && {
        echo "bsg-3"
        exit 0
}

MATCH=true
[ $LINES -eq 3 ] || MATCH=false
[ "$DEBUG" = "profile" ] && echo $MATCH
[[ $DATA =~ Stream\ #0:0.*(720x480) ]] || MATCH=false
[ "$DEBUG" = "profile" ] && echo $MATCH
[[ $DATA =~ Stream\ #0:1.*Audio:\ ac3.*stereo ]] || MATCH=false
[ "$DEBUG" = "profile" ] && echo $MATCH
[[ $DATA =~ Stream\ #0:2:\ Video:\ mjpeg ]] || MATCH=false
[ "$DEBUG" = "profile" ] && echo $MATCH
[ $MATCH = true ] && {
        echo "bsg-4"
        exit 0
}

MATCH=true
[ $LINES -eq 5 ] || MATCH=false
[ "$DEBUG" = "profile" ] && echo $MATCH
[[ $DATA =~ Stream\ #0:0.*(1920x1080) ]] || MATCH=false
[ "$DEBUG" = "profile" ] && echo $MATCH
[[ $DATA =~ Stream\ #0:1.*Audio:\ dts\ \(DTS-HD\ MA\).*5\.1 ]] || MATCH=false
[ "$DEBUG" = "profile" ] && echo $MATCH
[[ $DATA =~ Stream\ #0:2.*Audio:\ dts\ \(DTS\).*5\.1 ]] || MATCH=false
[ "$DEBUG" = "profile" ] && echo $MATCH
[[ $DATA =~ Stream\ #0:3.*Subtitle:\ hdmv_pgs_subtitle ]] || MATCH=false
[ "$DEBUG" = "profile" ] && echo $MATCH
[[ $DATA =~ Stream\ #0:4:\ Video:\ mjpeg ]] || MATCH=false
[ "$DEBUG" = "profile" ] && echo $MATCH
[ $MATCH = true ] && {
        echo "bsg-5"
        exit 0
}

MATCH=true
[ $LINES -eq 7 ] || MATCH=false
[ "$DEBUG" = "profile" ] && echo $MATCH
[[ $DATA =~ Stream\ #0:0.*(1920x1080) ]] || MATCH=false
[ "$DEBUG" = "profile" ] && echo $MATCH
[[ $DATA =~ Stream\ #0:1.*Audio:\ dts\ \(DTS-HD\ MA\).*5\.1 ]] || MATCH=false
[ "$DEBUG" = "profile" ] && echo $MATCH
[[ $DATA =~ Stream\ #0:2.*Audio:\ dts\ \(DTS\).*5\.1 ]] || MATCH=false
[ "$DEBUG" = "profile" ] && echo $MATCH
[[ $DATA =~ Stream\ #0:3.*Audio:\ ac3.*stereo ]] || MATCH=false
[ "$DEBUG" = "profile" ] && echo $MATCH
[[ $DATA =~ Stream\ #0:4.*Audio:\ ac3.*stereo ]] || MATCH=false
[ "$DEBUG" = "profile" ] && echo $MATCH
[[ $DATA =~ Stream\ #0:5.*Subtitle:\ hdmv_pgs_subtitle ]] || MATCH=false
[ "$DEBUG" = "profile" ] && echo $MATCH
[[ $DATA =~ Stream\ #0:6:\ Video:\ mjpeg ]] || MATCH=false
[ "$DEBUG" = "profile" ] && echo $MATCH
[ $MATCH = true ] && {
        echo "bsg-6"
        exit 0
}

MATCH=true
[ $LINES -eq 4 ] || MATCH=false
[ "$DEBUG" = "profile" ] && echo $MATCH
[[ $DATA =~ Stream\ #0:0.*(1920x1080) ]] || MATCH=false
[ "$DEBUG" = "profile" ] && echo $MATCH
[[ $DATA =~ Stream\ #0:1.*Audio:\ ac3.*stereo ]] || MATCH=false
[ "$DEBUG" = "profile" ] && echo $MATCH
[[ $DATA =~ Stream\ #0:2.*Subtitle ]] || MATCH=false
[ "$DEBUG" = "profile" ] && echo $MATCH
[[ $DATA =~ Stream\ #0:3:\ Video:\ mjpeg ]] || MATCH=false
[ "$DEBUG" = "profile" ] && echo $MATCH
[ $MATCH = true ] && {
        echo "bsg-7"
        exit 0
}

echo "No profile matched" >&2
exit 1
