Battlestar Galactica ripping. At the time I created this git repo,
this was by far the most sophisticated set of tools I'd developed.
It uses some of the scripts from the parent dir and adds some of
its own. `smart-encode.sh` is the main script, which does several
things.

The overall goal of this script is to be an idempotent "transcode
the entire series" script. That means it has to know how to encode
every single file ripped from the blurays and that when a file is
done, it doesn't try to process it again.

NOTE: The files this deals with had already been named according to
season and episode! The script doesn't actually deal with the raw,
ripped files. Maybe I could figure out the translation between the two
by ripping them all again and running checksums against both sets of
files.

To accomplish this, the script generally does the following things:

1. Scans a directory for all raw mkv's ripped from the BSG blurays.

1. Processes each mkv serially.

1. Skips the mkv if it's already been processed, noted by the
presence of a file named the same as the mkv file in the
`cache/done` directory.

1. Determines the "profile" that fits the file. Profiles are
manually created files in `data/profiles` that set some variables
when sourced, giving the script information about which streams to
keep and transcode.

1. Determines if the file is interlaced or not.

1. Determines the video quality (x265 CRF) to use for the mkv.

1. Determines a `complex_filter` chain, if necessary, based on
the presence of a file in `data/cuts` named the same as the mkv
being processed. This is how sections of a video get cut out.

1. Runs ffmpeg to transcode the video according to all the factors
it's discovered.

1. Writes the ffmpeg output to a file in `cache/log` named the same
as the mkv.

1. Touches the done file in `cache/done` when it finishes, but
only after checking the log output with the `done.sh` script.

Additional features:

Setting `QUALITY=rough` makes the script use a faster, lower-quality
video encoder and output to the ripping directory instead of the true
output directory. This feature lets you more quickly test any video
cuts you've made.
