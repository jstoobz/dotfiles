---
name: index
description: Scan ~/.stoobz/manifest.json for session artifacts and build a searchable index of past work. Use when the user says "/index", "find that session", "list my sessions", "what did I work on", "where was that investigation", or needs to locate a past session by topic or ticket. Supports filtering by tag, project, summary, label, or branch. Use --deep to search inside artifact content. Falls back to filesystem scan if no manifest exists.
---

# Index

Find and catalog past sessions from the `~/.stoobz/` archive.

## Process

### Manifest-First Path (default)

1. **Read `~/.stoobz/manifest.json`** — Parse the sessions array.

2. **Apply filter** (if user provided an argument):
   - `/index` → show all sessions
   - `/index <term>` → case-insensitive search across: `tags`, `summary`, `label`, `project`, `branch`
   - Multiple words are ANDed (all must match somewhere across fields)

3. **Present the index:**

```markdown
## Session Index — ~/.stoobz/manifest.json (N sessions)

| Project | Date | Label | Summary | Artifacts | Tags |
|---------|------|-------|---------|-----------|------|
| insurance | 2026-02-13 | ENG-23100 | Auth token refresh fix | T R P | elixir, auth |
| insurance | 2026-02-10 | auth-token-refresh | Token expiry investigation | T H P | elixir, phoenix |
| api-gateway | 2026-01-28 | rate-limiting | API rate limiting | T I | go, infrastructure |

**Legend:** T=TLDR C=Context R=Retro P=Prompt-Lab H=Handoff I=Investigation
```

   **Artifact abbreviations:**
   - `T` = TLDR.md
   - `C` = CONTEXT_FOR_NEXT_SESSION.md
   - `R` = RETRO.md
   - `P` = PROMPT_LAB.md
   - `H` = HANDOFF.md
   - `I` = INVESTIGATION_SUMMARY.md or INVESTIGATION_CONTEXT.md

4. **For each result**, show the `source_dir` so the user can `cd` there and `/pickup`.

5. **If user is searching**, highlight matching results and show the summary field for context.

### Deep Search — `--deep`

When invoked as `/index --deep <term>` (or `/index -d <term>`), search inside the actual archived artifact content:

1. **Grep `~/.stoobz/`** — Search all `.md` files under `~/.stoobz/` for the term (case-insensitive).

2. **Group by session** — Collect hits by their parent archive directory, not individual files.

3. **Present with context snippets:**

```markdown
## Deep Search — "auth-key" (2 hits across 1 session)

### utm / 2026-02-12-windex-usb-bundle
**TLDR.md:14** — ...couldn't set the **auth-key** properly in powershell while ssh'd in...
**INVESTIGATION_CONTEXT.md:87** — ...tailscale **auth-key** needs to be passed as...

Source: ~/utm
Tags: windows, deployment, infrastructure
```

4. **Also run manifest search** — Show manifest matches first (fast), then deep matches below. This way the user sees both metadata hits and content hits.

5. **If no manifest exists**, deep search still works — it's just grep over `~/.stoobz/`.

### Filesystem Fallback (no manifest)

If `~/.stoobz/manifest.json` doesn't exist:

1. **Notify the user:** "No manifest found. Falling back to filesystem scan..."

2. **Scan `~/.stoobz/`** for directories containing session artifacts (`TLDR.md`, `RETRO.md`, `PROMPT_LAB.md`, `HANDOFF.md`, `INVESTIGATION_SUMMARY.md`, `INVESTIGATION_CONTEXT.md`).

3. **For each directory found:**
   - Read the first 5 lines of `TLDR.md` (if present) for the title and date
   - Note which artifacts exist
   - Note the most recent modification date

4. **Present the index** in the same table format as above (without tags, since those come from the manifest).

5. **Suggest:** "Run `/park --archive-system` to build a manifest from these artifacts for faster future lookups."

## Rules

- **Read only headers** — Don't load full file contents. The manifest has everything needed; for fallback, first 5 lines of TLDR.md is enough.
- **Sort by date** — Most recent first.
- **Fast** — This is a lookup tool. Don't analyze, just catalog.
- **Suggest pickup** — If a result has a `source_dir` with `CONTEXT_FOR_NEXT_SESSION.md`, note: "Has resume context — run `/pickup` from that directory."
- **Present to the user directly** — Don't write a file (this is a query, not an artifact).
- **Manifest is truth** — When manifest exists, trust it. Don't re-scan the filesystem.
