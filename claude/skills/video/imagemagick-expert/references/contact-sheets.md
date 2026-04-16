# ImageMagick Contact Sheets

## Pattern Overview

Contact sheets for visual curation require three steps:
1. Extract/prepare a thumbnail per asset
2. Label each thumbnail with its index (and metadata like duration)
3. Tile thumbnails into a grid with `magick montage`

---

## Labeled Photo Thumbnail

```bash
FONT=/System/Library/Fonts/Supplemental/Georgia.ttf
idx=3   # display number

magick photo.jpg \
    -auto-orient \
    -resize 400x300^ -gravity Center -extent 400x300 \
    -gravity South \
    -background '#000000CC' -splice 0x30 \
    -gravity South -fill white \
    -font "$FONT" -pointsize 20 \
    -annotate +0+5 "#${idx}" \
    thumb.jpg
```

- `-resize 400x300^` — fill mode: scales up so both dimensions meet minimums, may crop
- `-gravity Center -extent 400x300` — crop to exact size, centered
- `-background '#000000CC'` — sets color for the `-splice` strip (hex RGBA, `CC` ≈ 80% opacity)
- `-splice 0x30` — adds 30px strip at the **gravity side** (South = bottom)
- `-annotate +0+5` — text sits 5px from bottom of the strip

For HEIC sources, convert first:
```bash
sips -s format jpeg photo.heic --out "${tmpdir}/raw.jpg" --resampleWidth 400 >/dev/null 2>&1
magick "${tmpdir}/raw.jpg" [same ops] thumb.jpg
```

---

## Labeled Clip Thumbnail (with Duration)

```bash
FONT=/System/Library/Fonts/Supplemental/Georgia.ttf
idx=2
clip=content/month-05/clip-01.mp4

# Extract frame at 1s (fallback to 0s)
ffmpeg -v quiet -y -ss 1 -i "$clip" -frames:v 1 -q:v 2 "${tmpdir}/frame.jpg" 2>/dev/null || \
ffmpeg -v quiet -y -ss 0 -i "$clip" -frames:v 1 -q:v 2 "${tmpdir}/frame.jpg"

dur=$(ffprobe -v quiet -show_entries format=duration -of csv=p=0 "$clip")
dur_label=$(printf "%.1fs" "$dur")

magick "${tmpdir}/frame.jpg" \
    -resize 400x300^ -gravity Center -extent 400x300 \
    -gravity South \
    -background '#000000CC' -splice 0x30 \
    -gravity South -fill white \
    -font "$FONT" -pointsize 18 \
    -annotate +0+5 "CLIP #${idx} (${dur_label})" \
    thumb-clip.jpg
```

---

## Contact Sheet Grid (magick montage)

```bash
FONT=/System/Library/Fonts/Supplemental/Georgia.ttf

magick montage "${tmpdir}"/labeled_*.jpg \
    -tile 5x \
    -geometry 400x330+4+4 \
    -background '#1a1a1a' \
    +label \
    -font "$FONT" \
    previews/month-05-photos.jpg
```

| Option | Meaning |
|--------|---------|
| `-tile 5x` | 5 columns, auto rows. Use `5x3` to fix rows too |
| `-geometry WxH+gx+gy` | Cell size + gutter between cells |
| `-background '#1a1a1a'` | Grid background (dark grey looks good) |
| `+label` | Suppress auto-generated filename labels under each cell |
| `-font` | Font for any auto-labels (keep set even with `+label`) |

Pass files as shell glob: `"${tmpdir}"/labeled_*.jpg` — sorted alphabetically, so name them with zero-padded indices (`001`, `002`, ...).

---

## Full Contact Sheet Workflow (Bash)

```bash
generate_contact_sheet() {
    local month="$1"
    local src_dir="$2"
    local out_dir="previews"
    local FONT=/System/Library/Fonts/Supplemental/Georgia.ttf

    mkdir -p "$out_dir"

    local photos=() clips=()
    for f in "$src_dir"/*; do
        [[ -f "$f" ]] || continue
        case "${f##*.}" in
            jpg|jpeg|png|JPG|JPEG|PNG|heic|HEIC) photos+=("$f") ;;
            mov|mp4|m4v|MOV|MP4|M4V)             clips+=("$f") ;;
        esac
    done

    # Photo sheet
    if [[ ${#photos[@]} -gt 0 ]]; then
        local tmpdir=$(mktemp -d)
        trap "rm -rf $tmpdir" RETURN
        local idx=0

        for photo in "${photos[@]}"; do
            idx=$((idx + 1))
            local ext="${photo##*.}"; local ext_l="${ext,,}"
            local raw="${tmpdir}/raw_${idx}.jpg"

            if [[ "$ext_l" == "heic" ]]; then
                sips -s format jpeg "$photo" --out "$raw" --resampleWidth 400 >/dev/null 2>&1
            else
                cp "$photo" "$raw"
            fi

            magick "$raw" \
                -auto-orient \
                -resize 400x300^ -gravity Center -extent 400x300 \
                -gravity South -background '#000000CC' -splice 0x30 \
                -gravity South -fill white -font "$FONT" -pointsize 20 \
                -annotate +0+5 "#${idx}" \
                "${tmpdir}/$(printf '%03d' $idx).jpg"
        done

        magick montage "${tmpdir}"/[0-9]*.jpg \
            -tile 5x -geometry 400x330+4+4 \
            -background '#1a1a1a' +label \
            "${out_dir}/month-${month}-photos.jpg"

        echo "  Photo sheet: ${out_dir}/month-${month}-photos.jpg (${#photos[@]} photos)"
    fi

    # Clip sheet
    if [[ ${#clips[@]} -gt 0 ]]; then
        local tmpdir=$(mktemp -d)
        trap "rm -rf $tmpdir" RETURN
        local idx=0

        for clip in "${clips[@]}"; do
            idx=$((idx + 1))
            local dur=$(ffprobe -v quiet -show_entries format=duration -of csv=p=0 "$clip")
            local dur_label=$(printf "%.1fs" "$dur")

            ffmpeg -v quiet -y -ss 1 -i "$clip" -frames:v 1 -q:v 2 "${tmpdir}/raw_${idx}.jpg" 2>/dev/null || \
            ffmpeg -v quiet -y -ss 0 -i "$clip" -frames:v 1 -q:v 2 "${tmpdir}/raw_${idx}.jpg"

            magick "${tmpdir}/raw_${idx}.jpg" \
                -resize 400x300^ -gravity Center -extent 400x300 \
                -gravity South -background '#000000CC' -splice 0x30 \
                -gravity South -fill white -font "$FONT" -pointsize 18 \
                -annotate +0+5 "CLIP #${idx} (${dur_label})" \
                "${tmpdir}/clip_$(printf '%03d' $idx).jpg"
        done

        magick montage "${tmpdir}"/clip_*.jpg \
            -tile 4x -geometry 400x330+4+4 \
            -background '#1a1a1a' +label \
            "${out_dir}/month-${month}-clips.jpg"

        echo "  Clip sheet:  ${out_dir}/month-${month}-clips.jpg (${#clips[@]} clips)"
    fi
}
```
