# Cross-Platform Shims (macOS / Linux)

## OS Detection

```bash
OS="$(uname -s)"
case "$OS" in
    Darwin) IS_MACOS=true  ;;
    Linux)  IS_MACOS=false ;;
    *)      echo "Unsupported OS: $OS"; exit 1 ;;
esac
```

---

## date

BSD (`macOS`) and GNU (`Linux`) have incompatible flags.

```bash
# Format a date string to "Month YYYY" (e.g., "March 2025")
format_month() {
    local year="$1" month="$2"
    local date_str="${year}-$(printf '%02d' "$month")-01"
    if $IS_MACOS; then
        date -j -f '%Y-%m-%d' "$date_str" '+%B %Y'
    else
        date -d "$date_str" '+%B %Y'
    fi
}

# Get current timestamp
timestamp() {
    if $IS_MACOS; then
        date -u '+%Y%m%d_%H%M%S'
    else
        date -u '+%Y%m%d_%H%M%S'  # same here, -u works on both
    fi
}
```

If the repo requires GNU date on macOS: `brew install coreutils` (installs as `gdate`).
Document this as a dependency rather than shimming everywhere.

---

## stat (File Size)

```bash
file_size() {
    local file="$1"
    if $IS_MACOS; then
        stat -f%z "$file"
    else
        stat -c%s "$file"
    fi
}
```

---

## sed (In-Place Edit)

BSD `sed -i` requires an extension argument (even empty); GNU doesn't:

```bash
sed_inplace() {
    if $IS_MACOS; then
        sed -i '' "$@"
    else
        sed -i "$@"
    fi
}

# Usage:
sed_inplace 's/foo/bar/g' file.txt
```

---

## HEIC Conversion

`sips` is macOS-only. On Linux, use `magick` (requires libheif):

```bash
convert_heic() {
    local input="$1" output="$2"
    if command -v sips &>/dev/null; then
        sips -s format jpeg "$input" --out "$output" >/dev/null 2>&1
    elif command -v magick &>/dev/null; then
        magick "$input" -auto-orient "$output"
    else
        echo "Error: cannot convert HEIC — install libheif (Linux) or use macOS" >&2
        return 1
    fi
}
```

---

## Dependency Checking

Run at the start of `bin/tool` before dispatching. Fail fast with a clear message:

```bash
check_deps() {
    local missing=()

    # Required
    for cmd in ffmpeg ffprobe jq python3 magick; do
        command -v "$cmd" &>/dev/null || missing+=("$cmd")
    done

    if [[ ${#missing[@]} -gt 0 ]]; then
        echo "Error: missing required dependencies: ${missing[*]}"
        echo ""
        echo "Install with:"
        if $IS_MACOS; then
            echo "  brew install ffmpeg imagemagick jq python3"
        else
            echo "  apt install ffmpeg imagemagick jq python3 python3-pip"
            echo "  pip3 install pyyaml"
        fi
        exit 1
    fi

    # Optional (warn, don't fail)
    command -v sips &>/dev/null || \
        warn "sips not found — HEIC conversion will use ImageMagick (requires libheif)"

    # Version checks
    local ffmpeg_ver
    ffmpeg_ver=$(ffmpeg -version 2>&1 | head -1 | grep -oE '[0-9]+\.[0-9]+' | head -1)
    local ffmpeg_major="${ffmpeg_ver%%.*}"
    if (( ffmpeg_major < 6 )); then
        warn "ffmpeg $ffmpeg_ver detected — version 6+ recommended"
    fi
}
```

---

## bash Version

macOS ships bash 3.2 (GPL). `mapfile` and some associative array features require bash 4+.

```bash
check_bash_version() {
    if (( BASH_VERSINFO[0] < 4 )); then
        echo "Error: bash 4+ required (found ${BASH_VERSION})"
        echo "  macOS: brew install bash"
        echo "  Then restart your terminal or run: exec bash"
        exit 1
    fi
}
```

Document the requirement prominently in README. Alternatively, avoid `mapfile` and associative arrays — bash 3.2 compatible alternatives exist for most uses.

---

## /usr/bin/bc vs bc

On macOS, `bc` can be aliased (`alias bc='brew cleanup'` is a real thing). Always use the full path:

```bash
# Never:
result=$(echo "1.5 * 30" | bc)

# Always:
result=$(echo "1.5 * 30" | /usr/bin/bc)
result=$(echo "1.5 * 30" | /usr/bin/bc -l)   # -l for float math
```

---

## Python3 Entry Point

Invoke the plan engine consistently:

```bash
PYTHON="${PYTHON:-python3}"

# Verify it works before using
"$PYTHON" --version &>/dev/null || {
    error "python3 not found — required for the plan engine"
}

"$PYTHON" "${ROOT}/engine/plan.py" "$CONFIG" "$@"
```

Allow `PYTHON=/path/to/python3 tool plan config.yml` override for virtualenv users.
