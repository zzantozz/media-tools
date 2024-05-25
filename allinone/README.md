This will be an attempt to make an all-in-one encode script that can
handle both movies and tv shows. I've got the movie part down pretty
well in the "movies" sibling dir.  My most sophisticated attempt at a
TV show is in the sibling "bsg" dir. The movies script is far more
advanced, but it lacks some things a tv show needs, like at least
setting "profiles" that determine what streams to keep based on
inspecting the streams, rather than having to write a config file for
every single show. Otoh, I'll need a config file per show for naming,
at least. We'll see what happens.

The main thing that'll need to differ from the movies script to work
for shows is the input and output file determination. It assumes a
flat input directory structure with a named movie dir full of movie
files. TV shows have nested season and disk dirs. Their output
structure is also multi-level, and tv specials don't work like movie
specials in Plex, either.

So far, I've used this to encode the entire Psych series, and it seem
to have worked. I was able to use hierarchical configs to put the
episodes in the "tv shows" library and the special features grouped
under a fake Psych movie folder. I haven't tried validating the config
files. It should fail hard for a couple of things. There's work to do
still!

Next up, try encoding some movies with this to see how it goes.

# IMPORTANT

A lot of this depends on MakeMKV settings. I rip with a minimum title
length of 30 seconds and this for title selection:

```
-sel:all,+sel:(favlang|nolang),-sel:mvcvideo,=100:all,-10:favlang,+sel:attachment
```

note: Here's how to update the videos encoded fast with gpu encoder to get better quality:

```
CACHEDIR=/mnt/d/ripping-work ONLY_MAP=true media-tools/allinone/encode.sh 2>&1 | tr '\n' '\0' | xargs -0 -I {} bash -c 'if ! [[ "{}" =~ IN:\ (.*)\ OUT:\ (.*) ]]; then echo "Skipping: {}"; else in="${BASH_REMATCH[1]}"; out="${BASH_REMATCH[2]}"; if ! [ -f "$out" ] || ffprobe -i "$out" 2>&1 | grep hevc_nvenc >/dev/null; then echo " *** re-encode $in"; CACHEDIR=/mnt/d/ripping-work/cache media-tools/allinone/encode.sh "$in"; else echo "already converted"; fi; fi'
```
