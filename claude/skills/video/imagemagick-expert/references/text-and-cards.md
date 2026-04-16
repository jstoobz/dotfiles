# ImageMagick Text & Title Cards

## Black Canvas Title Card (From Scratch)

```bash
FONT=/System/Library/Fonts/Supplemental/Georgia.ttf

magick -size 1920x1080 xc:black \
    -gravity Center \
    -font "$FONT" -fill white \
    -pointsize 72 -annotate +0-50 "Eliza's First Year" \
    -pointsize 40 -annotate +0+50 "2025–2026" \
    card-intro.png
```

- `xc:black` — X color canvas (solid fill). Also: `xc:white`, `xc:'#1a1a2e'`
- `-gravity Center` — all `-annotate` positions are relative to center
- `-annotate +X+Y` — offset from gravity point. `+0-50` = 50px above center
- Stack multiple `-pointsize -annotate` pairs for multi-line layouts

---

## Photo Title Card (Milestone Photo as Background)

```bash
FONT=/System/Library/Fonts/Supplemental/Georgia.ttf

magick photo.jpg \
    -auto-orient \
    -resize "1920x1080" \
    -gravity Center \
    -background black \
    -extent 1920x1080 \
    -gravity South \
    -font "$FONT" -fill white \
    -strokewidth 2 -stroke "rgba(0,0,0,0.6)" \
    -pointsize 48 -annotate +0+50 "May 2025" \
    -stroke none \
    -pointsize 48 -annotate +0+50 "May 2025" \
    card-month-01.png
```

The double `-annotate` draws a dark semi-transparent stroke pass, then a clean white pass on top — creating a readable outline without a hard border.

---

## The Stroke Outline Trick (Readable Text on Any Background)

Draw the same text twice: once with a stroke (shadow/outline), once clean:

```bash
-gravity South \
-font "$FONT" -fill white \
-strokewidth 2 -stroke "rgba(0,0,0,0.5)" \
-pointsize 42 -annotate +0+40 "Label Text" \
-stroke none \
-pointsize 42 -annotate +0+40 "Label Text"
```

**`-stroke none` is mandatory** after the stroke pass — it persists and will affect all subsequent draw operations if not reset.

For heavier shadow: increase `-strokewidth` (3–4) or use `"rgba(0,0,0,0.8)"`.

---

## Outro Card (Photo + Dark Scrim + Multiple Text Lines)

```bash
FONT=/System/Library/Fonts/Supplemental/Georgia.ttf

magick outro-photo.jpg \
    -auto-orient \
    -resize "1920x1080" -gravity Center -background black -extent 1920x1080 \
    -fill "rgba(0,0,0,0.55)" -draw "rectangle 0,820 1920,1080" \
    -gravity South \
    -font "$FONT" -fill white \
    -strokewidth 2 -stroke "rgba(0,0,0,0.5)" \
    -pointsize 64 -annotate +0+100 "Happy Birthday, Eliza!" \
    -stroke none \
    -pointsize 64 -annotate +0+100 "Happy Birthday, Eliza!" \
    -strokewidth 2 -stroke "rgba(0,0,0,0.5)" \
    -pointsize 36 -annotate +0+40 "Made with love" \
    -stroke none \
    -pointsize 36 -annotate +0+40 "Made with love" \
    card-outro.png
```

The `-draw "rectangle x0,y0 x1,y1"` paints a semi-transparent dark scrim over the lower portion of the image, giving the text a readable background without a harsh box.

For a scrim at any height: `y0 = HEIGHT - SCRIM_HEIGHT`.

---

## Plain Text on Black (Fallback Card)

When no photo is available:

```bash
magick -size 1920x1080 xc:black \
    -gravity Center \
    -font "$FONT" -fill white \
    -pointsize 56 -annotate +0-20 "May 2025" \
    -pointsize 28 -fill "rgba(255,255,255,0.6)" \
    -annotate +0+30 "Month 3" \
    card-month-03.png
```

Subdued subtitle: reduce `-fill` alpha (`rgba(255,255,255,0.6)`) for visual hierarchy.

---

## Converting PNG → Video (via ffmpeg)

Title cards are generated as PNG, then converted to video:

```bash
make_card() {
    local img="$1" out="$2" dur="$3" fade_in="${4:-0.8}" fade_out="${5:-0.5}"
    local fade_out_st
    fade_out_st=$(printf '%.6f' $(echo "$dur - $fade_out" | /usr/bin/bc))

    ffmpeg -y -loop 1 -i "$img" -t "$dur" \
        -vf "fps=30,fade=t=in:d=${fade_in},fade=t=out:st=${fade_out_st}:d=${fade_out}" \
        -c:v libx264 -crf 18 -pix_fmt yuv420p -an \
        "$out"
}

make_card build/card-intro.png build/card-intro.mp4 3.0 0.8 0.5
make_card build/card-month-01.png build/card-month-01.mp4 1.5 0.4 0.4
```
