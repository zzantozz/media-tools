#!/bin/bash

script_dir="$(cd "$(dirname "$0")" && pwd)"

. "$script_dir/allinone/utils"

usage() {
    cat << EOF
NAME
    $(basename "$0") - Monitor ffmpeg transcoding progress and estimate completion time

USAGE
    $(basename "$0") -i INPUT_FILE -l LOG_FILE
    $(basename "$0") -h

DESCRIPTION
    Analyzes an in-progress ffmpeg transcoding job by reading the source video
    metadata and monitoring the ffmpeg log file. Calculates progress percentage
    and estimates time remaining until completion.

OPTIONS
    -i INPUT_FILE
        Source video file being transcoded

    -l LOG_FILE
        FFmpeg log file to monitor for progress updates

    -h
        Display this help message and exit

EOF
}

source_video=""
log_file=""

while getopts "i:l:h" opt; do
    case "$opt" in
        i)
            source_video="$OPTARG"
            ;;
        l)
            log_file="$OPTARG"
            ;;
        h)
            usage
            exit 0
            ;;
        *)
            usage
            exit 1
            ;;
    esac
done

if [ -z "$source_video" ]; then
    die "Input video file (-i) is required"
fi

if [ -z "$log_file" ]; then
    die "Log file (-l) is required"
fi

# Check if source video exists
if [ ! -f "$source_video" ]; then
    die "Source video '$source_video' not found"
fi

# Check if log file exists
if [ ! -f "$log_file" ]; then
    die "Log file '$log_file' not found"
fi

# Get total frames using ffprobe (fast - reads from container metadata)
total_frames=$(ffprobe -v error -select_streams v:0 \
    -show_entries stream_tags=NUMBER_OF_FRAMES-eng -of default=noprint_wrappers=1:nokey=1 "$source_video" 2>/dev/null)

# Fallback: if NUMBER_OF_FRAMES-eng is not available, calculate from duration and fps
if [ -z "$total_frames" ] || [ "$total_frames" -eq 0 ]; then
    duration=$(ffprobe -v error -show_entries format=duration \
        -of default=noprint_wrappers=1:nokey=1 "$source_video" 2>/dev/null)
    fps=$(ffprobe -v error -select_streams v:0 -show_entries stream=r_frame_rate \
        -of default=noprint_wrappers=1:nokey=1 "$source_video" 2>/dev/null)
    
    # Convert fractional fps (e.g., "30000/1001") to decimal
    if [[ "$fps" == *"/"* ]]; then
        fps=$(echo "scale=3; $fps" | bc)
    fi
    
    total_frames=$(echo "scale=0; $duration * $fps / 1" | bc)
fi

if [ -z "$total_frames" ] || [ "$total_frames" -eq 0 ]; then
    die "Could not determine total frames from source video"
fi

echo "Total frames in source video: $total_frames"
echo ""

# Get the last line containing frame information
# ffmpeg writes status updates separated by \r, so we need to split on that
last_line=$(tr '\r' '\n' < "$log_file" | grep "frame=" | tail -1)

if [ -z "$last_line" ]; then
    die "No progress information found in log file"
fi

# Extract current frame and fps
current_frame=$(echo "$last_line" | grep -oP "frame=\s*\K\d+")
current_fps=$(echo "$last_line" | grep -oP "fps=\s*\K[\d.]+")

if [ -z "$current_frame" ] || [ -z "$current_fps" ]; then
    echo "Last line: $last_line"
    die "Could not parse progress information"
fi

# Calculate progress percentage
progress=$(echo "scale=2; $current_frame * 100 / $total_frames" | bc)

# Calculate remaining frames
remaining_frames=$(echo "$total_frames - $current_frame" | bc)

# Calculate estimated time remaining (in seconds)
if [ "$(echo "$current_fps > 0" | bc)" -eq 1 ]; then
    time_remaining_sec=$(echo "scale=0; $remaining_frames / $current_fps / 1" | bc)
    
    # Convert to hours:minutes:seconds
    hours=$(echo "$time_remaining_sec / 3600" | bc)
    minutes=$(echo "($time_remaining_sec % 3600) / 60" | bc)
    seconds=$(echo "$time_remaining_sec % 60" | bc)
    
    echo "Current progress:"
    echo "  Frame: $current_frame / $total_frames ($progress%)"
    echo "  Current FPS: $current_fps"
    echo "  Remaining frames: $remaining_frames"
    echo ""
    printf "Estimated time remaining: %02d:%02d:%02d\n" $hours $minutes $seconds
    
    # Calculate ETA (estimated time of completion)
    eta_timestamp=$(date -d "+${time_remaining_sec} seconds" "+%Y-%m-%d %H:%M:%S")
    echo "Estimated completion: $eta_timestamp"
else
    echo "Current progress:"
    echo "  Frame: $current_frame / $total_frames ($progress%)"
    echo "  Current FPS: $current_fps (too low to estimate)"
fi
