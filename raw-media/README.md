This is for keeping a record of what rips live where, since I started keeping the raw rips around on removable
SATA drives. Each folder corresponds to one of the drives and should have a description of the drive, the disks
it contains (output of `ls /mnt/<drive>/ripping`) and a full file listing (output of `find /mnt/<drive>/ripping`).

To record the contents of a disk, just come up with a label/name, like `raw-media-X` and then from this directory:

```
export LABEL=raw-media-X
export MOUNT=/mnt/Y
mkdir "$LABEL"
ls "$MOUNT/ripping" > "$LABEL/disks"
find "$MOUNT/ripping" > "$LABEL/full-list"
```

Then leave a README.md describing which disk it is.
