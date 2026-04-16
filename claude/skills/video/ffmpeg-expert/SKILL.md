---
name: ffmpeg-expert
description: ffmpeg patterns for video pipelines — filters, audio, concat, GIF generation, codec settings. Covers Ken Burns, letterbox, fade, multi-act assembly, and macOS gotchas.
---

# ffmpeg Expert

## Mental Model

```
inputs (-i) → [filter graph: -vf / -af / -filter_complex] → codec flags → output
```

- Filters chain with `,` — applied in order
- Named splits use `;` and `[labels]` — for complex graphs (split, overlay, amix)
- `-an` strips audio output; `-vn` strips video output
- `-map 0:v:0 -map 1:a:0` — explicit stream selection when merging inputs

## Quick Reference

| I need to... | Use |
|---|---|
| Photo → video with Ken Burns zoom | `→ references/filters.md` |
| Letterbox any source to 1920×1080 | `→ references/filters.md` |
| Fade video in/out | `→ references/filters.md` |
| Normalize fps + SAR before concat | `→ references/filters.md` |
| Loop a short song over a longer video | `→ references/audio.md` |
| Fade audio in/out | `→ references/audio.md` |
| Merge separate video + audio files | `→ references/audio.md` |
| Fix silent audio after concat | `→ references/audio.md` (sample rate) |
| Join pre-built segments | `→ references/pipeline-patterns.md` |
| Multi-act pipeline with per-act music | `→ references/pipeline-patterns.md` |
| Extract a frame from video | `→ references/pipeline-patterns.md` |
| Create a quality GIF | `→ references/gif.md` |
| Boomerang / speed-ramped GIF | `→ references/gif.md` |

## Must-Know Gotchas

| Issue | Fix |
|---|---|
| `bc` aliased | Use `/usr/bin/bc` explicitly |
| BSD `date` rejects GNU flags | `date -j -f '%Y-%m-%d' "YYYY-MM-DD" '+%B %Y'` |
| HEIC not recognized | `brew install libheif` |
| Glob matches nothing → literal string passed | `shopt -s nullglob` at script top |
| `fade=t=out:st=` uses scientific notation | `printf '%.6f' $(echo "$d - $f" \| /usr/bin/bc)` |
| Audio silent after concat | Mismatched sample rates — add `-ar 48000` to all audio prep |
| DTS errors in concat | Mixed fps or SAR — normalize before joining |
| ffmpeg 8: `-framerate` on concat removed | Use `duration` directive in list file instead |
| Zoompan pixelates at zoom | Render at 2× resolution, downscale after (see filters.md) |

## Codec Defaults (Standard Pipeline)

```bash
-c:v libx264 -crf 18 -preset slow -pix_fmt yuv420p   # archival quality
-c:v libx264 -crf 26 -preset medium                   # shareable / preview
-c:a aac -b:a 192k -ar 48000                          # audio (always set -ar)
-movflags +faststart                                   # web streaming
```

CRF scale: 0 = lossless, 18 = high quality, 23 = default, 28 = small file, 51 = worst.

## ffprobe — Get Duration

```bash
ffprobe -v quiet -show_entries format=duration -of csv=p=0 "$file"
# returns float seconds, e.g. 12.345678
```

## References

- `references/filters.md` — Ken Burns/zoompan, letterbox, fade, fps/SAR normalization, drawtext
- `references/audio.md` — stream_loop, afade, sample rate, audio merge patterns
- `references/pipeline-patterns.md` — concat demuxer, photo→video, multi-act assembly
- `references/gif.md` — two-pass palette, boomerang, speed, size optimization
