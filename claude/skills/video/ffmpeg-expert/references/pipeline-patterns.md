# ffmpeg Pipeline Patterns

## Photo → Video (Looped Still)

```bash
ffmpeg -y -loop 1 -i photo.jpg \
    -t 3.5 \
    -vf "scale=3840:2160:force_original_aspect_ratio=decrease,\
pad=3840:2160:(ow-iw)/2:(oh-ih)/2:black,\
zoompan=z='1.0+0.001*on':d=105:x='iw/2-(iw/zoom/2)':y='ih/2-(ih/zoom/2)':s=3840x2160:fps=30,\
scale=1920:1080,\
fade=t=in:d=0.3,fade=t=out:st=3.2:d=0.3" \
    -c:v libx264 -crf 18 -pix_fmt yuv420p -an \
    output.mp4
```

`-loop 1` treats the image as an infinite source. `-t` caps output duration.

---

## Concat Demuxer

Joins pre-built segments. Use when all segments share the same codec, resolution, fps, and SAR.

```bash
# Build list file with absolute paths
> list.txt
for seg in segment-*.mp4; do
    echo "file '$(pwd)/${seg}'" >> list.txt
done

# Re-encode (safe, always works)
ffmpeg -y -f concat -safe 0 -i list.txt \
    -c:v libx264 -crf 18 -pix_fmt yuv420p \
    -c:a aac -b:a 192k \
    output.mp4

# Stream copy (fast, only if codecs match perfectly)
ffmpeg -y -f concat -safe 0 -i list.txt \
    -c copy \
    output.mp4
```

**Absolute paths + `-safe 0` are both required.** Relative paths fail with `unsafe file name` error.

### Per-Segment Duration Override (ffmpeg 8+)
The `-framerate` input option was removed in ffmpeg 8. To control timing per segment, use the `duration` directive:

```
file '/abs/path/segment-01.mp4'
duration 2.5
file '/abs/path/segment-02.mp4'
duration 4.0
```

---

## Multi-Act Pipeline

Pattern for a video with multiple acts, each with its own music track:

```
Step 1: Build silent segments per month
Step 2: Concat months into per-act silent video
Step 3: Loop/trim song to match act duration + fade audio
Step 4: Merge audio onto act video
Step 5: Concat acts into final video
```

```bash
# Step 2 — silent act video
ffmpeg -y -f concat -safe 0 -i act-1-list.txt \
    -c:v libx264 -crf 18 -pix_fmt yuv420p -an \
    build/act-1-video.mp4

# Step 3 — song audio trimmed/looped to act duration
ACT_DUR=$(ffprobe -v quiet -show_entries format=duration -of csv=p=0 build/act-1-video.mp4)
FADE_OUT_ST=$(printf '%.6f' $(echo "$ACT_DUR - 2" | /usr/bin/bc))
ffmpeg -y -stream_loop -1 -i music/01-song.mp3 \
    -t "$ACT_DUR" \
    -af "afade=t=in:d=2,afade=t=out:st=${FADE_OUT_ST}:d=2" \
    -c:a aac -b:a 192k -ar 48000 \
    build/act-1-audio.m4a

# Step 4 — merge
ffmpeg -y -i build/act-1-video.mp4 -i build/act-1-audio.m4a \
    -c:v copy -c:a aac -b:a 192k \
    -map 0:v:0 -map 1:a:0 \
    build/act-1-merged.mp4

# Step 5 — final concat (re-encode for robustness)
ffmpeg -y -f concat -safe 0 -i final-list.txt \
    -c:v libx264 -crf 18 -preset slow -pix_fmt yuv420p \
    -c:a aac -b:a 192k \
    -movflags +faststart \
    output/montage-final.mp4
```

---

## Normalize a Clip (Resolution + Codec + FPS + SAR)

```bash
DUR=$(ffprobe -v quiet -show_entries format=duration -of csv=p=0 clip.mov)
FADE_OUT_ST=$(printf '%.6f' $(echo "$DUR - 0.3" | /usr/bin/bc))

ffmpeg -y -i clip.mov \
    -vf "scale=1920:1080:force_original_aspect_ratio=decrease,\
pad=1920:1080:(ow-iw)/2:(oh-ih)/2:black,\
setsar=1,fps=30,\
fade=t=in:d=0.3,fade=t=out:st=${FADE_OUT_ST}:d=0.3" \
    -c:v libx264 -crf 18 -preset slow -pix_fmt yuv420p \
    -an \
    normalized.mp4
```

Handles: portrait video, variable fps, non-square SAR, MOV/MP4/M4V input.

---

## Frame Extraction

```bash
# Single frame at 1 second (for thumbnails)
ffmpeg -v quiet -y -ss 1 -i clip.mp4 -frames:v 1 -q:v 2 frame.jpg

# Fallback if clip is shorter than 1s
ffmpeg -v quiet -y -ss 1 -i "$clip" -frames:v 1 -q:v 2 frame.jpg 2>/dev/null || \
ffmpeg -v quiet -y -ss 0 -i "$clip" -frames:v 1 -q:v 2 frame.jpg

# Frame at midpoint (for thumbnails/posters)
DUR=$(ffprobe -v quiet -show_entries format=duration -of csv=p=0 video.mp4)
MID=$(echo "$DUR / 2" | /usr/bin/bc)
ffmpeg -y -i video.mp4 -ss "$MID" -frames:v 1 -q:v 2 thumbnail.jpg
```

`-q:v 2` = high quality JPEG (scale: 1–31, lower is better).

---

## Generate Shareable (Compressed) Version

```bash
ffmpeg -y -i output/montage-final.mp4 \
    -vf "scale=-2:720" \
    -c:v libx264 -crf 26 -preset medium \
    -c:a aac -b:a 128k \
    -movflags +faststart \
    output/montage-shareable.mp4
```

`scale=-2:720` — 720p height, width auto-calculated to nearest even number (required for yuv420p).
