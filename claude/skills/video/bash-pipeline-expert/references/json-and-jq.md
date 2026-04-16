# JSON & jq Patterns

## Why JSON (Not YAML) in Bash

Bash scripts never parse YAML — that's Python's job. The Python plan engine reads `config.yml` and emits `.build/plan/plan.json`. Bash scripts consume JSON via `jq`. This keeps the boundary hard and avoids the yq version fragmentation problem.

```
config.yml  →  [Python engine]  →  .build/plan/plan.json  →  [bash scripts via jq]
```

---

## Reading Scalar Values

```bash
PLAN=".build/plan/plan.json"

# String
PROJECT_ID=$(jq -r '.project.id' "$PLAN")

# Number
TOTAL_DURATION=$(jq -r '.summary.total_duration_seconds' "$PLAN")

# Boolean
HAS_INTRO=$(jq -r '.config.has_intro_card' "$PLAN")

# Nested
ACT1_SONG=$(jq -r '.acts[0].song' "$PLAN")
```

`-r` = raw output (strips JSON string quotes). Always use `-r` for string values you'll use in bash.

---

## Iterating Over JSON Arrays

```bash
# Iterate over act IDs
jq -r '.acts[].id' "$PLAN" | while IFS= read -r act_id; do
    echo "Processing act: $act_id"
done

# Iterate with index
jq -r '.acts | to_entries[] | "\(.key) \(.value.id)"' "$PLAN" | \
while read -r idx act_id; do
    echo "Act $((idx + 1)): $act_id"
done
```

**Warning:** `while read` runs in a subshell in bash — variables set inside won't persist after the loop. Collect into an array first if you need them later:

```bash
# Collect act IDs into array
mapfile -t ACT_IDS < <(jq -r '.acts[].id' "$PLAN")

for act_id in "${ACT_IDS[@]}"; do
    echo "Act: $act_id"
done
```

`mapfile` (aka `readarray`) is bash 4+. macOS ships bash 3.2 (GPL licensing). Check or require bash 4:
```bash
(( BASH_VERSINFO[0] >= 4 )) || { echo "bash 4+ required (brew install bash)"; exit 1; }
```

---

## Per-Asset Iteration

The intake index has one entry per asset. Render loop pattern:

```bash
INDEX=".build/intake/index.json"

# Get asset count
ASSET_COUNT=$(jq '.assets | length' "$INDEX")

# Iterate: extract multiple fields per asset in one jq call
jq -c '.assets[]' "$INDEX" | while IFS= read -r asset; do
    path=$(echo "$asset" | jq -r '.path')
    kind=$(echo "$asset" | jq -r '.kind')
    act=$(echo "$asset" | jq -r '.act_id')
    duration=$(echo "$asset" | jq -r '.timing.duration')
    fade_in=$(echo "$asset" | jq -r '.timing.fade_in')

    case "$kind" in
        hero_photo)   process_photo "$path" "$duration" "$fade_in" ;;
        burst_photo)  process_photo "$path" "$duration" "$fade_in" ;;
        video_clip)   process_clip  "$path" "$duration" ;;
    esac
done
```

`-c` = compact output (one JSON object per line). Feed it to `while read` for per-item processing.

---

## Filtering and Selecting

```bash
# Get assets for a specific act
jq -c '.assets[] | select(.act_id == "act1")' "$INDEX"

# Get only hero photos
jq -c '.assets[] | select(.kind == "hero_photo")' "$INDEX"

# Get assets with effects
jq -c '.assets[] | select(.effects | length > 0)' "$INDEX"

# Get overridden assets
jq -c '.assets[] | select(.overridden == true)' "$INDEX"
```

---

## Null/Missing Value Safety

```bash
# Default if field is null or missing
duration=$(jq -r '.timing.duration // 3.5' <<< "$asset")

# Check if field exists before using
has_override=$(jq -r 'if .override then "true" else "false" end' <<< "$asset")
```

`//` is jq's alternative operator — returns right side if left is `null` or `false`.

---

## Building JSON in Bash (for intake.sh)

When bash scripts need to emit JSON (e.g., `intake.sh` building the asset index), use `jq` to construct it rather than string interpolation:

```bash
# Append an asset entry to the index
add_asset() {
    local path="$1" kind="$2" act_id="$3" duration="$4"
    local index_file="$5"

    jq -n \
        --arg path "$path" \
        --arg kind "$kind" \
        --arg act_id "$act_id" \
        --argjson duration "$duration" \
        '{path: $path, kind: $kind, act_id: $act_id, timing: {duration: $duration}}' \
        >> "${index_file}.tmp"
}

# After all assets: wrap array
jq -s '.' "${index_file}.tmp" > "$index_file"
rm "${index_file}.tmp"
```

`--arg` passes strings; `--argjson` passes already-parsed JSON (numbers, booleans, objects).
**Never** build JSON via string interpolation (`echo "{\"path\": \"$path\"}"`) — breaks on special characters.

---

## Validating plan.json Exists Before Running

```bash
PLAN=".build/plan/plan.json"

[[ -f "$PLAN" ]] || {
    error "plan.json not found — run 'intake' and 'plan' first"
}

# Validate it's valid JSON
jq empty "$PLAN" 2>/dev/null || {
    error "plan.json is malformed — re-run 'plan'"
}
```
