[ -f "analyze-audit" ] || {
  echo "You're running this in the wrong place. There should be an existing"
  echo "file called 'analyze-audit' in this directory."
  echo "If you're running it for the first time, just touch 'analyze-audit'."
  exit 1
}

find /mnt/d/ripping-work/cache/analyze/ -type f -print0 | sort -z | xargs -0 -I {} bash -c 'line="{}"; unset INTERLACED; source "$line"; config="$INTERLACED"; rel="${line/\/mnt\/d\/ripping-work\/cache\/analyze\//}"; if grep "$rel" analyze-audit &>/dev/null; then done=true; fi; if ! [ "$done" = true ]; then video="/mnt/l/ripping/$rel"; if ! [ -f "$video" ]; then echo "SKIP - $rel"; skip=true; fi; if [ "$skip" != true ]; then actual="$(bash ~/media-tools/interlaced.sh -f video -i "$video" || echo " ^^ Failed to detect interlacing for $rel" >&2)"; if [ "$config" = "$actual" ]; then echo "OK   - $rel"; else echo "BAD  - $rel"; fi; fi; fi' >> analyze-audit
