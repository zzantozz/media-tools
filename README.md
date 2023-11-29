# Media encoding pipeline

This project contains my work on automatically converting my physical dvds/blurays to digital.
Many of the scripts and files here go back many years, long before the creation of this GitHub
repo. They're still here partly for historical reference and partly because I just haven't
taken the time to clean up the old as the new stuff emerges.

## History

Roughly, the generations of tooling goes:

1. [Old tools](old) - These are my very earliest attempts at having scripts to handle repetitive tasks.

2. Tools in the root of this project - The next set of tools, aimed at breaking things down into more
   useful pieces. Some of the scripts here are still used by the latest generation.

3. The [BSG encoder](bsg) - Handled the BSG box set. Here, I began the idea of recording data about titles
   inside this project so that if/when I have to rip and encode again, I already know what everything is.
   The solution wasn't perfect, but it set me on a path. I believe this is also what introduced idempotent
   encoding by keeping track of successful encodes. This meant a source directory could be processed
   repeatedly without doing unnecessary work.

4. Dedicated [movie handling](movies) - Based on success with BSG, this expands the idea of mapping the raw,
   ripped titles via config files, but only for movies.

5. The [allinone project](allinone) - Took the movies project and extended it to support tv shows as well.
   The aim here is that once the proper data files are created, any disk can be correctly ripped and transcoded
   without any further effort. It keeps idempotency so that you can just rip a bunch of disks to an input
   directory and run the encoder over and over to handle all the new titles without redoing work.

## Current workflow

Since there's so much old stuff scattered around, some of it intertwined, here's the current workflow:

1. Have a Linux box and Plex. Most of the scripts here are meant to run in Linux, and I use Plex to organize my
   media, so everything here is oriented at that.

2. Clone this project.

3. Use [`rip-a-disk.sh`](rip-a-disk.sh) to grab titles of an inserted dvd or bluray. This uses `makemkvcon -r info`
   to get a disk's info and stores it. It uses that to get the disk title, and then creates an output directory
   named that and rips all titles into that directory.

   > **Note:** This script isn't perfect yet, since it still relies on profile settings created by running the
     MakeMKV gui. Make sure to use a minimum title length of 30 seconds to match existing data!

   > **Note2:** Despite what step 1 says, I normally run this script from a Git Bash shell on a windows box. I've
     had better luck with MakeMKV there.

4. Use [`check-title-overlap.sh`](check-title-overlap.sh) to inspect the info file written by the previous step.
   It helps find titles that overlap or contain other titles. For example, special features or deleted scenes will
   often appear both as a single title containing all of them and as individual titles per scene. This helps you
   figure out which titles you actually want to map to outputs. (I usually delete the input titles that I don't
   care to keep at this point.)

5. Create [config files for the disk](allinone/data/config). They should be named the same as the disk and title files.
   There can/should also be a file named `main` that sets global defaults for everything in the directory, like the
   name of the movie/tv show. Existing files should make it easy to see how to set things up generally.

6. Run the [allineone encode script](allinone/encode.sh). It will start by complaining about several directories
   that you need to set. I won't explain all of them here. Once set up correctly, it will process all the input
   titles into output files based on the config data provided.

7. Point Plex at the output files.

## Guidelines

General rules for modern scripts:

1. If passed no args, print some usage info.

2. Write modular scripts that focus on cohesive operations. (Do one thing and do it well.)

3. Write result to stdout. Write debug and errors to stderr.

4. Turn on debug info when the DEBUG var contains the name of the script.
