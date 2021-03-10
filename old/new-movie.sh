#!/bin/bash

[ "$1" = "" ] && {
    echo "First arg should be path to input movie file"
    exit 1
}
[ "$2" = "" ] && {
    echo "Second arg should be real movie name with year, like: 'The Greatest Showman (2017)'"
    exit 1
}
[ "$MOVIE_BASE_DIR" = "" ] && MOVIE_BASE_DIR="/mnt/x/movies"
INPUT_FILE=$(basename "$1")
MOVIE_NAME="$2"
MOVIE_OUT_DIR="$MOVIE_BASE_DIR/$2"
OUTPUT_FILE="$MOVIE_OUT_DIR/$2.mkv"

echo "Creating Plex movie dir"
echo "  input: $1"
echo "  movie dir: $MOVIE_OUT_DIR"
echo "  create directory structure ..."

should ffmpeg the file instead of rsyn - set movie title in metadata - video stream only if possible

mkdir -p "$MOVIE_OUT_DIR"
mkdir -p "$MOVIE_OUT_DIR/Behind The Scenes"
mkdir -p "$MOVIE_OUT_DIR/Deleted Scenes"
mkdir -p "$MOVIE_OUT_DIR/Featurettes"
mkdir -p "$MOVIE_OUT_DIR/Interviews"
mkdir -p "$MOVIE_OUT_DIR/Scenes"
mkdir -p "$MOVIE_OUT_DIR/Shorts"
mkdir -p "$MOVIE_OUT_DIR/Trailers"

rsync -avc "$1" "$MOVIE_OUT_DIR"

