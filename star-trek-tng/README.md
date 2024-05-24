I made this directory to hold stuff about encoding the Star Trek TNG bluray collection.
Mainly it's a place to put the files that contain titles to filter out of encoding for
various reasons.

**IMPORTANT NOTE**: I had already deleted many titles that would fall into these categories
while reviewing the titles to create configs for them. Therefore, these lists aren't complete.
They're here for future reference and a reminder of how I approached the problem.

The files are:

- `tng-filtering` - This is the initial file that contains all of the non-episode titles with durations and
sizes. I used this to sort them all by duration and find titles with the same or similar duration. That let
me identify all the groups of titles below.

- `tng-cat-blank-5min` - Lots of the disks have a 5-minute, all-black title. I don't know what it is, but
it's easy to find by duration, and the size is really small since it's all black.

- `tng-cat-garbage-backgrounds` - One of the bluray background menus. There are multiple because it looks
like they made them fancier over time.

- `tng-cat-garbage-backgrounds-2` - One of the bluray background menus. There are multiple because it looks
like they made them fancier over time.

- `tng-cat-garbage-backgrounds-3` - One of the bluray background menus. There are multiple because it looks
like they made them fancier over time.

- `tng-cat-garbage-pinkstuff` - This also occurs on a lot of the disks. It's some text in a foreign language
with a weird, swirly, pink background. No idea what it is, but I don't need it.

- `tng-cat-previews` - This isn't necessarily something to filter out. It's TV spots/teasers for upcoming
episodes, like "Next time on Star Trek...". They're all about 32-34 seconds in length. I didn't encode them
individually, because who would want to go through 177 of these things? This command successfully concatenates
them all into one video because it might be interesting to have it as a special feature:

    ```
     ripping_dir=/mnt/l/ripping/ && rm -f concats && ( cat tng-cat-previews | cut -d ' ' -f 3- | sort | grep '^./STAR' && cat tng-cat-previews | cut -d ' ' -f 3- | sort | grep -v '^./STAR' ) | sed "s#^./#$ripping_dir/#" | xargs -I {} bash -c "echo \"file '{}'\" >> concats" && ffmpeg -f concat -safe 0 -i concats -c copy /mnt/plex-media/encoded/out.mkv
    ```

I built the initial file of all non-episode titles like this:

```
comm -23 <(cd /mnt/l/ripping && find -type f -ipath '*/star trek *' -not -path '*/backup/*' -not -name '_info*' | sort) <(cd ~/media-tools/allinone/data/config/ && find -type f -ipath '*/star trek *' -not -name 'main' | sort) | tr '\n' '\0' | xargs -0 -I {} bash -c 'abs="/mnt/l/ripping/{}"; duration="$(ffprobe -show_entries format=duration -v quiet -of csv="p=0" -i "$abs")"; size=$(wc -c < "$abs"); echo "$duration $size {}"' > tng-filtering
```

To find categories within the main file, use a command like this. To work with following commands, make
sure to name them according to the pattern `tng-cat-*`:

```
cat tng-filtering | sort -n | awk '$1>36.87 && $1<=42.592' > tng-cat-garbage-pinkstuff
```

After building all the category files, I used this to create configs to encode everything in the initial
list, excluding the titles that fell into the identifiable categories. It's just a first pass at getting them
encoded without knowing what they are. I hope to update the configs with better data in the future:

```
rm -rf tmp; mkdir tmp; comm -23 <(cat tng-filtering | sort) <(cat tng-cat-* | sort) | sort -k 3 | cut -d ' ' -f 3- | tr '\n' '\0' | xargs -0 -I {} bash -c 'input="{}"; [[ "$input" =~ The\ Next\ Generation\ Season\ (.)\ Dis[ck]\ (.) ]] && season="${BASH_REMATCH[1]}" && disk="${BASH_REMATCH[2]}"; [[ "$input" =~ TNG\ S(.)\ D(.) ]] && season="${BASH_REMATCH[1]}" && disk="${BASH_REMATCH[2]}"; n=1; found_id=false; while [ "$found_id" = false ]; do id="s${season}d${disk} - $n"; if [ -f "tmp/$id" ]; then n=$((n+1)); else found_id=true; fi; done; touch "tmp/$id"; output="Star Trek The Next Generation/Other/Unknown - $id.mkv"; config="media-tools/allinone/data/config/$input"; if [ -f "$config" ]; then echo "$config already exists!"; else echo "OUTPUTNAME=\"$output\"" > "$config"; echo "KEEP_STREAMS=all" >> "$config"; fi'
```

You can make a VLC playlist out of one or more file lists with a command like

```
cat tng-cat-* | cut -d ' ' -f 3- | tr '\n' '\0' | xargs -0 -I {} echo 'l:\ripping\{}' > playlist.vlc
```
