# ImageMagick Transforms

## Letterbox (Contain Mode)

Scales to fit inside the target canvas. Preserves full image, adds black bars.

```bash
magick photo.jpg \
    -auto-orient \
    -resize "1920x1080" \
    -gravity Center \
    -background black \
    -extent 1920x1080 \
    output.png
```

- `-auto-orient` — applies EXIF rotation from phone photos. **Always add this first.**
- `-resize "WxH"` (no `^`) — scales so the longest dimension fits; aspect ratio preserved
- `-gravity Center` + `-extent` — pads remaining space symmetrically with `-background` color

---

## Crop / Fill Mode

Scales to fill the canvas completely. May clip sides or top/bottom.

```bash
magick photo.jpg \
    -auto-orient \
    -resize "1920x1080^" \
    -gravity Center \
    -extent 1920x1080 \
    output.png
```

`^` suffix on `-resize` means "scale so both dimensions meet or exceed target". `-extent` then crops the overflow from center.

Use this for cover art, backgrounds, or when you want no black bars.

---

## HEIC Conversion

**Via `sips` (always available on macOS, no install required):**
```bash
# Convert single file
sips -s format jpeg input.heic --out output.jpg >/dev/null 2>&1

# Convert with resize (good for thumbnails)
sips -s format jpeg input.heic --out output.jpg --resampleWidth 400 >/dev/null 2>&1
```

**Via `magick` (requires `brew install libheif`):**
```bash
magick input.heic -auto-orient output.jpg
```

`sips` is the reliable fallback — always present on macOS, no dependencies. Use `magick` when you need ImageMagick's full pipeline (resize + annotate + output in one command).

---

## Dark Scrim Overlay

Semi-transparent dark rectangle over part of a photo — for text contrast without a harsh box:

```bash
HEIGHT=1080
SCRIM_TOP=820   # starts 260px from bottom

magick photo.jpg \
    -auto-orient \
    -resize "1920x1080" -gravity Center -background black -extent 1920x1080 \
    -fill "rgba(0,0,0,0.55)" \
    -draw "rectangle 0,${SCRIM_TOP} 1920,${HEIGHT}" \
    output.png
```

`-draw "rectangle x0,y0 x1,y1"` fills with the current `-fill` color. For a full-width bottom strip: `x0=0, x1=WIDTH, y0=HEIGHT-SCRIM_HEIGHT, y1=HEIGHT`.

Adjust opacity (`0.55`) for lighter or heavier scrims.

---

## Compositing (Overlay One Image on Another)

```bash
# Overlay a logo/watermark at bottom-right
magick base.jpg \
    \( logo.png -resize 200x100 \) \
    -gravity SouthEast -geometry +20+20 \
    -composite \
    output.jpg
```

- `\( ... \)` — sub-expression: process the inner image independently
- `-geometry +X+Y` — offset from gravity anchor
- `-composite` — apply the overlay using the default `Over` operator

---

## Color Operations

```bash
# Adjust brightness/contrast
magick photo.jpg -brightness-contrast 5x10 output.jpg

# Desaturate to grayscale
magick photo.jpg -colorspace Gray output.jpg

# Slight color temperature warm
magick photo.jpg -color-matrix "1.1 0 0  0 1 0  0 0 0.9" output.jpg

# Vignette (darken edges)
magick photo.jpg \
    -background black \
    -vignette 0x40+5+5 \
    output.jpg
```

---

## Batch HEIC → JPEG (Directory)

```bash
for f in source/*.heic source/*.HEIC; do
    [[ -f "$f" ]] || continue
    base=$(basename "${f%.*}")
    sips -s format jpeg "$f" --out "output/${base}.jpg" >/dev/null 2>&1
done
```

Using `sips` in a loop is fast and requires no dependencies. For quality-critical work, use `magick` instead (respects color profiles more carefully).

---

## Resize Reference

| Goal | `-resize` flag | Result |
|------|---------------|--------|
| Fit inside WxH (letterbox) | `-resize "WxH"` | Scaled down, aspect preserved, may have bars |
| Fill WxH (crop) | `-resize "WxH^"` | Scaled up to fill, may clip |
| Force exact WxH (distort) | `-resize "WxH!"` | Ignores aspect ratio |
| Limit longest dimension | `-resize "Nx"` or `-resize "xN"` | Scales on one axis |
| Only shrink, never enlarge | `-resize "WxH>"` | No-op if already smaller |
| Only enlarge, never shrink | `-resize "WxH<"` | No-op if already larger |
