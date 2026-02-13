---
name: park
description: Park the current session by generating all session artifacts, archiving them to ~/.stoobz/<project>/<date-label>/, and updating the manifest. Use when the user says "/park", "park this session", "wrap up", "I'm done for now", "save everything", or wants to create a complete handoff package before leaving a session. Runs /tldr, /relay, and /prompt-lab in sequence, then archives. Supports --archive-system for retroactive cleanup of scattered artifacts.
---

# Park Session

Generate all session artifacts, archive them to `~/.stoobz/`, and clean up cwd. The "I'm stepping away, save everything" command.

## Process

### Phase 1 — Generate Artifacts

1. **Announce** — Tell the user: "Parking this session. Generating artifacts..."

2. **Run each skill in sequence:**
   - `/tldr` → `TLDR.md` — Shareable session summary
   - `/relay` → `CONTEXT_FOR_NEXT_SESSION.md` — Resume context for next session
   - `/prompt-lab` → `PROMPT_LAB.md` — Original + optimized prompt

3. **For each skill, follow its full process** including:
   - Checking for existing files (merge, don't overwrite)
   - Using the correct output format from each skill's spec
   - Applying each skill's rules

### Phase 2 — Archive

4. **Determine project name:**
   - If in a git repo: `basename $(git rev-parse --show-toplevel)`
   - Otherwise: `basename $(pwd)`

5. **Determine label** (first match wins):
   - User provided an argument to `/park <label>` → use that label
   - Git branch name (if not `main`, `master`, `develop`) → use branch name
   - Slugify the first heading from TLDR.md → use that (max 50 chars, lowercase, hyphens)
   - Fallback → date only (no label suffix)

6. **Build archive path:**
   - Pattern: `~/.stoobz/<project>/<YYYY-MM-DD>-<label>/`
   - If path already exists, append `-2`, `-3`, etc.
   - `mkdir -p` the path

7. **Copy artifacts to archive:**

   | Copy to archive | Leave in cwd |
   |----------------|--------------|
   | `TLDR.md` | `CONTEXT_FOR_NEXT_SESSION.md` |
   | `PROMPT_LAB.md` | |
   | `RETRO.md` (if exists) | |
   | `HANDOFF.md` (if exists) | |
   | `INVESTIGATION_SUMMARY.md` (if exists) | |
   | `INVESTIGATION_CONTEXT.md` (if exists) | |
   | `evidence/` (if exists, `cp -r`) | |

8. **Clean up cwd** — Remove the copied artifacts from cwd (not `CONTEXT_FOR_NEXT_SESSION.md` — it stays as the relay baton for `/pickup`).

9. **Update manifest** — Read-modify-write `~/.stoobz/manifest.json`:
   - If file doesn't exist, create it with `{"sessions": []}`
   - If file is corrupted/unparseable, back it up as `manifest.json.bak` and create fresh
   - Check if an entry with the same `archive_path` already exists → update in place
   - Otherwise append a new entry

   **Manifest entry schema:**
   ```json
   {
     "id": "<YYYY-MM-DD>-<label>",
     "project": "<project-name>",
     "date": "<YYYY-MM-DD>",
     "label": "<label>",
     "summary": "<first heading text from TLDR.md>",
     "source_dir": "<absolute path to cwd>",
     "archive_path": "<project>/<YYYY-MM-DD>-<label>",
     "branch": "<git branch or null>",
     "artifacts": ["TLDR.md", "PROMPT_LAB.md"],
     "tags": ["elixir", "auth"],
     "type": "session"
   }
   ```

   **Tags** — Auto-detect 2-5 tags from TLDR.md content:
   - Languages: elixir, python, javascript, typescript, ruby, go, rust, sql
   - Frameworks: phoenix, ecto, oban, react, next, absinthe, liveview
   - Topics: debugging, performance, migration, refactor, investigation, auth, deployment, testing, infrastructure

10. **Print summary:**

```
Session parked and archived.

  Archive:  ~/.stoobz/<project>/<date-label>/
  Artifacts archived: TLDR.md, PROMPT_LAB.md
  Relay:    CONTEXT_FOR_NEXT_SESSION.md (stays in cwd)
  Tags:     elixir, phoenix, auth

  Run /pickup in this directory to resume.
  Run /index to find past sessions.
```

## `--archive-system` — Retroactive Cleanup

When invoked as `/park --archive-system`, skip artifact generation and instead archive existing scattered artifacts:

1. **Scan for artifacts** — Run `find ~ -maxdepth 4 -type d -name ".stoobz"` and also scan common project roots for loose session artifacts (`TLDR.md`, `RETRO.md`, `HANDOFF.md`, `PROMPT_LAB.md`, `INVESTIGATION_SUMMARY.md`, `INVESTIGATION_CONTEXT.md`) that aren't already under `~/.stoobz/`.

2. **Present findings:**

```markdown
## Found Session Artifacts

| # | Location | Artifacts | Date | Summary |
|---|----------|-----------|------|---------|
| 1 | ~/projects/insurance/.stoobz/ENG-23100/ | T R P | 2026-02-10 | Auth token refresh fix |
| 2 | ~/work/api/TLDR.md | T | 2026-02-08 | API rate limiting |
| 3 | ~/projects/insurance/.stoobz/memory-leaks/ | T C H | 2026-01-28 | BEAM memory investigation |

Archive all? [Y/n] or specify numbers to skip.
```

3. **For each selected location:**
   - Determine project name from the git repo or parent directory
   - Determine label from directory name, branch, or TLDR heading
   - Copy (not move) artifacts to `~/.stoobz/<project>/<date-label>/`
   - Update `~/.stoobz/manifest.json` with each entry
   - Ask before removing source files: "Remove originals from `<path>`? [y/N]"

4. **Skip** any artifacts already under `~/.stoobz/` (already archived).

5. **Print summary** with count of sessions archived and manifest location.

## Rules

- **All or nothing** (Phase 1) — Generate all three core artifacts. For individual artifacts, use the specific skill.
- **Always archive** — Phase 2 runs automatically after Phase 1. No flag needed.
- **Respect existing files** — Each skill handles its own file existence check.
- **Don't re-explain** — Just execute. The user wants results, not descriptions.
- **No questions** — Generate all three without asking. Use best judgment for content.
- **CONTEXT_FOR_NEXT_SESSION.md never moves** — It stays in cwd as the relay baton for `/pickup`.
- **Manifest is append-only** — Never remove entries, only add or update in place.
- **Idempotent** — Re-parking the same session updates the existing archive entry rather than creating duplicates.
