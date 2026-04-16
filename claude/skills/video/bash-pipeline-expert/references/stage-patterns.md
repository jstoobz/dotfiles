# Stage Patterns

## Idempotent Stages

Each stage checks for its output artifact before running. Re-running the pipeline skips completed stages automatically.

```bash
# Standard stage guard
STAGE_ARTIFACT="${BUILD_DIR}/.stage-render-complete"

if [[ -f "$STAGE_ARTIFACT" ]] && [[ "${FORCE:-false}" != "true" ]]; then
    success "Render already complete — skipping (use --force to re-run)"
    exit 0
fi

# ... do the work ...

touch "$STAGE_ARTIFACT"
success "Render complete"
```

Stage artifact naming convention:
```
.build/
  .stage-intake-complete
  .stage-plan-complete
  .stage-render-complete
  .stage-package-complete
```

---

## Invalidating Downstream Stages

When a stage re-runs (due to `--force` or changed inputs), remove downstream stage markers:

```bash
invalidate_downstream() {
    local stage="$1"
    case "$stage" in
        intake)
            rm -f "${BUILD_DIR}"/.stage-{plan,render,package}-complete
            ;;
        plan)
            rm -f "${BUILD_DIR}"/.stage-{render,package}-complete
            ;;
        render)
            rm -f "${BUILD_DIR}"/.stage-package-complete
            ;;
    esac
}

# In intake.sh, after completing:
touch "${BUILD_DIR}/.stage-intake-complete"
invalidate_downstream intake
```

---

## Resume from Step

The dispatcher passes `--from` to all scripts; each script checks if it should run:

```bash
# In each stage script, at the top:
FROM_STEP="${FROM_STEP:-}"    # set by dispatcher from --from flag

should_run() {
    local this_step="$1"
    # If no --from, always run
    [[ -z "$FROM_STEP" ]] && return 0
    # Run if this step comes at or after --from in pipeline order
    local order=(intake plan render package)
    local from_idx=-1 this_idx=-1 i=0
    for step in "${order[@]}"; do
        [[ "$step" == "$FROM_STEP" ]] && from_idx=$i
        [[ "$step" == "$this_step" ]] && this_idx=$i
        ((i++))
    done
    (( this_idx >= from_idx ))
}

should_run "render" || { success "Skipping render (before --from point)"; exit 0; }
```

Usage:
```bash
tool render config.yml --from render    # skip intake + plan, re-run render + package
```

---

## Temp File Cleanup with Trap

```bash
TMPDIR_WORK=$(mktemp -d)
CLEANUP_FILES=()

cleanup() {
    rm -rf "$TMPDIR_WORK"
    # Clean up any named temp files registered at runtime
    for f in "${CLEANUP_FILES[@]:-}"; do
        rm -f "$f"
    done
}
trap cleanup EXIT

# Register additional temp files as they're created:
TMPFILE=$(mktemp /tmp/palette-XXXXX.png)
CLEANUP_FILES+=("$TMPFILE")
```

`trap cleanup EXIT` fires on normal exit, error exit, and `set -e` failures. `EXIT` is more reliable than `ERR` + `INT` combined.

---

## Parallel Jobs with Concurrency Cap

Run multiple ffmpeg encode jobs concurrently without overwhelming the machine:

```bash
MAX_JOBS="${MAX_JOBS:-4}"   # configurable, default 4
job_count=0
job_pids=()

wait_for_slot() {
    while (( ${#job_pids[@]} >= MAX_JOBS )); do
        # Wait for any job to finish
        for i in "${!job_pids[@]}"; do
            if ! kill -0 "${job_pids[$i]}" 2>/dev/null; then
                # Job finished — check exit status
                wait "${job_pids[$i]}" || { error "Background job failed"; }
                unset 'job_pids[$i]'
                job_pids=("${job_pids[@]}")   # repack array
                break
            fi
        done
        sleep 0.1
    done
}

# In the render loop:
for photo in content/month-*/photo-*.jpg; do
    wait_for_slot
    process_photo "$photo" "${BUILD_DIR}/$(basename "$photo").mp4" &
    job_pids+=($!)
done

# Wait for all remaining jobs
for pid in "${job_pids[@]:-}"; do
    wait "$pid" || { error "A background job failed"; }
done
```

For simple cases where order doesn't matter and failures are catastrophic, `xargs -P` is simpler:
```bash
printf '%s\n' content/month-*/photo-*.jpg | xargs -P 4 -I{} bash -c 'process_photo "$1"' _ {}
```

---

## Build Directory Convention

```
project-root/
  .build/
    intake/
      index.json            ← Python intake output
    plan/
      plan.json             ← Python plan output
      plan.txt              ← human-readable timing tables
    segments/
      month-01-item-01.mp4  ← per-element encoded files
    acts/
      act-1-video.mp4
      act-1-audio.m4a
      act-1-merged.mp4
    .stage-intake-complete
    .stage-plan-complete
    .stage-render-complete
  output/
    <project-id>-1080p.mp4
    <project-id>-720p.mp4
    <project-id>-thumbnail.jpg
```

`.build/` is gitignored. `output/` can be optionally gitignored or committed.

---

## Dry Run Pattern

`--dry-run` prints what would happen without encoding anything:

```bash
run_ffmpeg() {
    if [[ "${DRY_RUN:-false}" == "true" ]]; then
        echo "  [dry-run] ffmpeg ${*}"
        return 0
    fi
    ffmpeg "$@"
}

# Use run_ffmpeg everywhere instead of ffmpeg directly
run_ffmpeg -y -loop 1 -i "$photo" -t 3.5 -vf "..." output.mp4
```

For the plan stage, dry-run is free — it only does math, never encodes. Advertise this:
```bash
# plan.sh is always safe to run — it never modifies media files
# Use --dry-run on render/package to preview without encoding
```
