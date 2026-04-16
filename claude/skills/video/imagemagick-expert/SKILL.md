---
name: imagemagick-expert
description: ImageMagick patterns for video pipeline work — title cards, contact sheets, thumbnails, text annotation, HEIC conversion, letterboxing, and color overlays.
---

# ImageMagick Expert

## Mental Model

```
magick [input | -size WxH xc:color] → [operations in order] → output
```

- Operations are applied left to right and modify the **current image state**
- `-gravity` sets the anchor for all subsequent `-annotate`, `-extent`, and `-splice` calls — reset it explicitly when switching
- `-background` affects `-extent`, `-splice`, and canvas creation
- Settings like `-font`, `-fill`, `-stroke`, `-pointsize` persist until changed — always reset `-stroke none` after stroking

## Quick Reference

| I need to... | Use |
|---|---|
| Title card from scratch (black canvas + text) | `→ references/text-and-cards.md` |
| Text on a photo with readable outline | `→ references/text-and-cards.md` (stroke trick) |
| Multi-line text card with different sizes | `→ references/text-and-cards.md` |
| Letterbox a photo to 1920×1080 | `→ references/transforms.md` |
| Crop-fill a photo (no black bars) | `→ references/transforms.md` |
| Dark scrim overlay for text contrast | `→ references/transforms.md` |
| Numbered thumbnail for contact sheet | `→ references/contact-sheets.md` |
| Grid of photo thumbnails | `→ references/contact-sheets.md` |
| Grid of clip thumbnails with duration labels | `→ references/contact-sheets.md` |
| Convert HEIC to JPEG | `→ references/transforms.md` |

## Must-Know Gotchas

| Issue | Fix |
|---|---|
| EXIF rotation ignored | Always add `-auto-orient` before any resize |
| Stroke bleeds into next text | Reset with `-stroke none` after every stroke pass |
| `-splice` adds to wrong side | It adds to the side set by `-gravity` (South = bottom) |
| `convert` vs `magick` | Use `magick` (v7+). `convert` still works but is legacy |
| Font not found | Use full TTF path, not font name. Run `magick -list font` to verify |
| `-gravity` affects `-extent` | Set to `Center` before `-extent` for centered letterbox |
| HEIC support missing | `brew install libheif` for `magick`, or use `sips` as fallback |

## macOS Font Paths

```bash
/System/Library/Fonts/Supplemental/Georgia.ttf        # serif, reliable
/System/Library/Fonts/HelveticaNeue.ttc               # sans-serif
/System/Library/Library/Fonts/Supplemental/Arial.ttf  # fallback
```

Use full paths in scripts. SF Pro (system UI font) is not directly accessible to ImageMagick.

`magick -list font` — shows all fonts ImageMagick can find by name (not always reliable cross-machine).

## Temp File Pattern

For multi-step batch processing:

```bash
tmpdir=$(mktemp -d)
trap "rm -rf $tmpdir" EXIT

for photo in "${photos[@]}"; do
    magick "$photo" [ops] "${tmpdir}/labeled_$(printf '%03d' $idx).jpg"
done

magick montage "${tmpdir}"/labeled_*.jpg [montage opts] output.jpg
```

## References

- `references/text-and-cards.md` — title cards, annotation gravity, multi-line, stroke outline trick
- `references/contact-sheets.md` — labeled thumbnails, magick montage, clip sheets
- `references/transforms.md` — letterbox, crop, HEIC, dark overlays, color operations
