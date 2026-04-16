# ffmpeg Audio Patterns

## Strip Audio from Output

```bash
ffmpeg -y -i input.mp4 -c:v copy -an output.mp4
```

Use `-an` whenever building silent video segments. Keeps intermediate files clean and avoids audio codec mismatch issues downstream.

---

## Loop a Short Song to Fill a Longer Video

```bash
ACT_DUR=110   # seconds
FADE=2
FADE_OUT_ST=$(printf '%.6f' $(echo "$ACT_DUR - $FADE" | /usr/bin/bc))

ffmpeg -y -stream_loop -1 -i song.mp3 \
    -t "$ACT_DUR" \
    -af "afade=t=in:d=${FADE},afade=t=out:st=${FADE_OUT_ST}:d=${FADE}" \
    -c:a aac -b:a 192k -ar 48000 \
    act-audio.m4a
```

- `-stream_loop -1` — loop input infinitely; `-t` caps total output duration
- `-ar 48000` — normalize sample rate. **Critical** when acts will be concatenated with `-c:v copy`. Mismatched rates produce silent seams or "invalid pts" errors.
- `-af afade` — audio fade in/out. `st=` is start time in seconds.

If song is longer than act, it auto-trims to `-t`. No special handling needed.

---

## Merge Video + Audio Files

```bash
ffmpeg -y -i video.mp4 -i audio.m4a \
    -c:v copy \
    -c:a aac -b:a 192k \
    -map 0:v:0 -map 1:a:0 \
    merged.mp4
```

- `-c:v copy` — no video re-encode (fast, lossless)
- `-map 0:v:0` — video from first input
- `-map 1:a:0` — audio from second input
- Explicit `-map` avoids ffmpeg picking the wrong stream when inputs have mixed tracks

---

## Crossfade Between Two Audio Tracks

```bash
# Prepare track A to fade out at the end
# Prepare track B to fade in at the start
# Then concat — the overlapping fades create a perceptual crossfade

# Or use amix for true overlap (more complex):
ffmpeg -y -i track_a.m4a -i track_b.m4a \
    -filter_complex "\
[0:a]atrim=0:${OVERLAP},afade=t=out:st=0:d=${OVERLAP}[a_fade];\
[1:a]afade=t=in:d=${OVERLAP}[b_fade];\
[a_fade][b_fade]amix=inputs=2:duration=first[out]" \
    -map "[out]" \
    -c:a aac -b:a 192k -ar 48000 \
    crossfaded.m4a
```

For most montage pipelines: prepare each act's audio with matching fade-out/fade-in durations (`SONG_CROSSFADE=2`), then concatenate acts normally. True overlap amix isn't necessary.

---

## Extract Audio from Video

```bash
# Copy audio stream (no re-encode, fast)
ffmpeg -y -i source.mp4 -vn -c:a copy extracted.m4a

# Re-encode to AAC (normalize codec)
ffmpeg -y -i source.mp4 -vn -c:a aac -b:a 192k -ar 48000 extracted.m4a
```

Use `-vn` to skip video processing. `-c:a copy` is fastest when the source audio is already AAC.

---

## Diagnosing Audio Issues

```bash
# Check audio stream details
ffprobe -v quiet -show_streams -select_streams a "$file" | grep -E "codec|sample_rate|channels"

# Expected output for a normalized pipeline:
# codec_name=aac
# sample_rate=48000
# channels=2
```

Common silent-audio causes after concat:
1. Sample rate mismatch between acts (fix: `-ar 48000` on all audio prep)
2. No audio stream in one segment (fix: ensure all merged acts have audio before final concat)
3. `-c copy` on segments with different audio codecs (fix: re-encode with `-c:a aac`)
