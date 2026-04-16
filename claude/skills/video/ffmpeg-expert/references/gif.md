# ffmpeg GIF Generation

## Why Two-Pass Palette

GIF is limited to 256 colors. A single-pass encode uses a generic palette — banding and dithering artifacts are obvious on smooth gradients (skin, sky, motion blur).

Two-pass: first pass analyzes the actual frames and generates an optimized palette; second pass encodes using that palette.

## Standard Two-Pass GIF

```bash
INPUT=clip.mp4
OUTPUT=output.gif
WIDTH=480
FPS=15
SPEED=1.0   # 1.0 = normal, 0.5 = half speed, 2.0 = double

PALETTE=$(mktemp /tmp/palette-XXXXX.png)
trap "rm -f $PALETTE" EXIT

FILTERS="fps=${FPS},setpts=PTS/${SPEED},scale=${WIDTH}:-1:flags=lanczos"

ffmpeg -v quiet -i "$INPUT" \
    -vf "${FILTERS},split[s0][s1];\
[s0]palettegen=max_colors=128:stats_mode=diff[p];\
[s1][p]paletteuse=dither=floyd_steinberg" \
    "$OUTPUT"
```

### Palette Options

| Option | Effect |
|--------|--------|
| `max_colors=128` | Smaller palette → smaller file, less color accuracy (default: 256) |
| `stats_mode=diff` | Optimize palette for motion (changes between frames) — best for video |
| `stats_mode=full` | Optimize for overall color coverage — better for static content |
| `dither=floyd_steinberg` | Best dithering for smooth gradients and skin tones |
| `dither=none` | Sharper edges, worse gradients — good for pixel art or flat graphics |

### Size vs Quality Levers

| To reduce file size... | Trade-off |
|------------------------|-----------|
| Lower `--fps` (12–15 is sweet spot) | Choppier motion |
| Smaller `--width` (360–480) | Lower resolution |
| Lower `max_colors` (64–128) | More color banding |
| Shorter `DURATION` | Less content |
| Higher `SPEED` (1.5–2.0) | Faster playback |

Target: **under 5MB for iMessage**. Check with `stat -f%z output.gif`.

---

## Boomerang (Forward + Reversed Loop)

```bash
INPUT=clip.mp4
OUTPUT=boomerang.gif
WIDTH=480; FPS=15

TMPCLIP=$(mktemp /tmp/clip-XXXXX.mp4)
REVERSED=$(mktemp /tmp/rev-XXXXX.mp4)
CONCAT_LIST=$(mktemp /tmp/list-XXXXX.txt)
JOINED=$(mktemp /tmp/joined-XXXXX.mp4)
trap "rm -f $TMPCLIP $REVERSED $CONCAT_LIST $JOINED" EXIT

# Extract segment
ffmpeg -v quiet -y -ss 00:00:01 -t 1.5 -i "$INPUT" \
    -c:v libx264 -crf 18 -an "$TMPCLIP"

# Reverse
ffmpeg -v quiet -y -i "$TMPCLIP" -vf "reverse" -c:v libx264 -crf 18 -an "$REVERSED"

# Concat forward + reversed
echo "file '${TMPCLIP}'" > "$CONCAT_LIST"
echo "file '${REVERSED}'" >> "$CONCAT_LIST"
ffmpeg -v quiet -y -f concat -safe 0 -i "$CONCAT_LIST" -c:v libx264 -crf 18 -an "$JOINED"

# Two-pass palette
FILTERS="fps=${FPS},scale=${WIDTH}:-1:flags=lanczos"
ffmpeg -v quiet -y -i "$JOINED" \
    -vf "${FILTERS},split[s0][s1];\
[s0]palettegen=max_colors=128:stats_mode=diff[p];\
[s1][p]paletteuse=dither=floyd_steinberg" \
    "$OUTPUT"
```

---

## GIF with Caption

Add white text at the bottom:

```bash
CAPTION="me on mondays"
FILTERS="fps=15,scale=480:-1:flags=lanczos,\
drawtext=text='${CAPTION}':fontcolor=white:fontsize=24:\
borderw=2:bordercolor=black:\
x=(w-text_w)/2:y=h-th-16"

ffmpeg -v quiet -i input.mp4 \
    -vf "${FILTERS},split[s0][s1];\
[s0]palettegen=max_colors=128:stats_mode=diff[p];\
[s1][p]paletteuse=dither=floyd_steinberg" \
    output.gif
```

Escape single quotes in caption text: `text='it'\''s fine'`

---

## GIF + MP4 Pair

For sharing: GIF for previewing in chats, MP4 for full quality. Same source segment:

```bash
# GIF (palette-optimized, small)
ffmpeg -i clip.mp4 -vf "fps=15,scale=480:-1:flags=lanczos,split[s0][s1];\
[s0]palettegen=stats_mode=diff[p];[s1][p]paletteuse=dither=floyd_steinberg" \
    output.gif

# MP4 (1080p quality, for video players)
ffmpeg -y -i clip.mp4 \
    -vf "scale=1920:1080:force_original_aspect_ratio=decrease,pad=1920:1080:(ow-iw)/2:(oh-ih)/2:black" \
    -c:v libx264 -crf 18 -pix_fmt yuv420p -an \
    output-1080p.mp4
```
