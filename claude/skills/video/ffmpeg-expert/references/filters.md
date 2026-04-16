# ffmpeg Video Filters

## Ken Burns (Zoompan on Photos)

### The 2× Resolution Trick
Render zoompan at 2× target resolution, then downscale. Without this, zoompan interpolates at 1× and looks soft at zoom edges.

```bash
W=1920; H=1080; FPS=30; DURATION=3.5; CRF=18
ZP_W=$((W * 2))    # 3840
ZP_H=$((H * 2))    # 2160
TOTAL_FRAMES=$(echo "$DURATION * $FPS / 1" | /usr/bin/bc)
ZOOM_RATE=$(echo "0.15 / $TOTAL_FRAMES" | /usr/bin/bc -l)
FADE=0.3
FADE_OUT_ST=$(printf '%.6f' $(echo "$DURATION - $FADE" | /usr/bin/bc))

# Zoom in (even items)
ZOOM_EXPR="z='1.0+${ZOOM_RATE}*on'"

# Zoom out (odd items)
ZOOM_EXPR="z='1.15-${ZOOM_RATE}*on'"

ffmpeg -y -loop 1 -i photo.jpg \
    -vf "scale=${ZP_W}:${ZP_H}:force_original_aspect_ratio=decrease,\
pad=${ZP_W}:${ZP_H}:(ow-iw)/2:(oh-ih)/2:black,\
zoompan=${ZOOM_EXPR}:d=${TOTAL_FRAMES}:\
x='iw/2-(iw/zoom/2)':y='ih/2-(ih/zoom/2)':s=${ZP_W}x${ZP_H}:fps=${FPS},\
scale=${W}:${H},\
fade=t=in:d=${FADE},fade=t=out:st=${FADE_OUT_ST}:d=${FADE}" \
    -t "$DURATION" \
    -c:v libx264 -crf "$CRF" -pix_fmt yuv420p -an \
    output.mp4
```

### Zoompan Parameters
| Parameter | Meaning |
|-----------|---------|
| `z=` | Zoom level expression. 1.0 = no zoom, 1.5 = 50% zoomed in |
| `d=` | Duration in **frames** (not seconds) |
| `on` | Current frame number, 1-based |
| `x=`, `y=` | Pan offset. `iw/2-(iw/zoom/2)` keeps subject centered |
| `s=` | Output size from zoompan filter (set to 2× for quality) |
| `fps=` | Output fps — must match pipeline fps |

### Burst Photos (Snappier, Shorter Duration)
```bash
BURST_DURATION=1.0
BURST_FADE=0.15
BURST_FRAMES=$(echo "$BURST_DURATION * $FPS / 1" | /usr/bin/bc)
# Use same zoom_expr, just lower d= and tighter fades
```

---

## Letterbox / Scale + Pad

Fit any aspect ratio to target resolution, black bars on sides or top:

```bash
-vf "scale=1920:1080:force_original_aspect_ratio=decrease,\
pad=1920:1080:(ow-iw)/2:(oh-ih)/2:black,\
setsar=1"
```

- `force_original_aspect_ratio=decrease` — scales down to fit, never crops
- `pad` — centers and fills remaining space with black
- `setsar=1` — resets Sample Aspect Ratio to square pixels (required before concat)

### Crop / Fill Mode (may clip edges)
```bash
-vf "scale=1920:1080:force_original_aspect_ratio=increase,\
crop=1920:1080"
```

---

## Fades

```bash
# Fade in only
-vf "fade=t=in:d=0.3"

# Fade in + out — compute st carefully to avoid scientific notation
DURATION=5.0
FADE=0.3
FADE_OUT_ST=$(printf '%.6f' $(echo "$DURATION - $FADE" | /usr/bin/bc))
-vf "fade=t=in:d=${FADE},fade=t=out:st=${FADE_OUT_ST}:d=${FADE}"

# On clips with dynamic duration
DUR=$(ffprobe -v quiet -show_entries format=duration -of csv=p=0 clip.mp4)
FADE_OUT_ST=$(printf '%.6f' $(echo "$DUR - 0.3" | /usr/bin/bc))
-vf "fade=t=in:d=0.3,fade=t=out:st=${FADE_OUT_ST}:d=0.3"
```

`printf '%.6f'` prevents scientific notation (e.g. `1e-1`) that ffmpeg rejects in filter args.

---

## FPS + SAR Normalization

Always apply before joining segments. Mixed sources cause "non-monotonous DTS" or audio sync issues.

```bash
-vf "scale=1920:1080:force_original_aspect_ratio=decrease,\
pad=1920:1080:(ow-iw)/2:(oh-ih)/2:black,\
setsar=1,\
fps=30"
```

Order matters: scale → pad → setsar → fps.

---

## drawtext (Overlay Text on Video)

Burn text into video at encode time:

```bash
-vf "drawtext=\
fontfile=/System/Library/Fonts/Supplemental/Georgia.ttf:\
text='Hello World':\
fontsize=48:\
fontcolor=white:\
borderw=2:\
bordercolor=black:\
x=(w-text_w)/2:\
y=h-th-20"
```

- `x=(w-text_w)/2` — horizontally centered
- `y=h-th-20` — 20px from bottom
- `borderw`/`bordercolor` — outline (alternative to shadow)
- Escape single quotes in text: `text='it'\''s fine'`

For dynamic text per-frame, use ImageMagick to generate PNG title cards and convert to video instead (simpler to control).
