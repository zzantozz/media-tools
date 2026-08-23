This is for keeping a record of what rips live where, since I started keeping the raw rips around on removable
SATA drives. Each folder corresponds to one of the drives and should have a description of the drive, the disks
it contains (output of `ls /mnt/<drive>/ripping`) and a full file listing (output of `find /mnt/<drive>/ripping`).

To record the contents of a disk, just come up with a label/name, like `raw-media-X` and then from this directory:

```
export LABEL=raw-media-X
export MOUNT=/mnt/Y
mkdir "$LABEL" && ls "$MOUNT/ripping" > "$LABEL/disks" && find "$MOUNT/ripping" > "$LABEL/full-list"
```

Current drive labels:

- `raw-media-1`: L: drive, containing `ADV_SHERLOCK_SIDEA`

- `raw-media-2`: K: drive, containing `50 First Dates - Big Daddy`

- `raw-media-3`: J: drive, containing `Abbott and Costello Meet Frankenstein`

NOTE: I often just use a `find` across the media drives instead of
this because 1) I forget about it and/or 2) this can be out of date. I
could fix that second thing by setting up a cron job to update it
daily. Would that be a good idea?