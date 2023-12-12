This dir is for a PoC of searchable "disk signatures" that will let you match
a disk against known disk info. In other words, you just put a disk in a drive
and run some script/program that gathers info about it and searches a database
to figure out what disk it is.

My initial idea for this is to store info about each title of a disk in a db row.
The info can be gathered by `makemkvcon info`. One way to find a disk is to look
for a collection of titles with certain lengths. So a db row could be as simple as

| diskId | titleIndex | titleLength |
| ------ | ---------- | ----------- |
| foo    | 1          | 120         |
| foo    | 2          | 150         |
| foo    | 3          | 10          |
| bar    | 1          | 150         |
| bar    | 2          | 120         |

The `diskId` would be a key that identifies the disk and probably refers to some other
data somewhere. The `titleIndex` isn't the title number, since if you're ripping with
MakeMKV, then title numbers change based on your selected min title length. Instead,
it's just a relative title index showing order of titles. The `titleLength` is length
in seconds.

This way, you can take any number of titles from a disk you have and search for them.
Example searches and results:

- Search for one title with length 10. Result: disk "foo" because it's the only one
  with a title of that length.

- Search for one title with length 150. Result: disks "foo" and "bar" because both have
  a title of the requested length.

- Search for two titles with lengths [120, 150]. Result: only disk "foo" - while "bar"
  also has titles of those lengths, they're in the wrong order.

