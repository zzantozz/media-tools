My personal scripts/tools for media transcoding.

This is just a bunch of stuff I've used over the years
to manage my media library. It largely consists of
scripts that run ffmpeg to do various stuff.

They're here so I don't lose them when the drive they
live on dies.

General rules for modern scripts:

1. If passed no args, print some usage info.

1. Write modular scripts that focus on cohesive operations.

1. Write result to stdout. Write debug and errors to stderr.

1. Turn on debug info when the DEBUG var is set to the name of the script.
