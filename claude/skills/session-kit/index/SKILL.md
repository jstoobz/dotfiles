---
name: index
description: Scan .stoobz directories for session artifacts and build a searchable index of past work. Use when the user says "/index", "find that session", "list my sessions", "what did I work on", "where was that investigation", or needs to locate a past session by topic or ticket. Scans for TLDR.md, CONTEXT_FOR_NEXT_SESSION.md, and other artifacts across .stoobz directories.
---

# Index

Find and catalog past sessions across `.stoobz/` directories.

## Process

1. **Determine search scope:**
   - Default: scan the nearest `.stoobz/` directory (project-level first, then `~/.stoobz/`)
   - If user specifies "all" or "everything": scan both project and global `.stoobz/`
   - If user provides a search term: filter results by topic/ticket

2. **Scan for session directories** — Walk `.stoobz/` looking for directories containing session artifacts (`TLDR.md`, `CONTEXT_FOR_NEXT_SESSION.md`, `RETRO.md`, `PROMPT_LAB.md`, `HANDOFF.md`).

3. **For each directory found:**
   - Read the first 5 lines of `TLDR.md` (if present) for the title and date
   - Note which artifacts exist
   - Note the most recent modification date

4. **Present the index:**

```markdown
## Session Index — {scope}

| Directory                     | Date       | Summary                         | Artifacts |
| ----------------------------- | ---------- | ------------------------------- | --------- |
| `PROJ-XXXXX/qa-investigation`   | 2026-02-06 | Statusline + session kit skills | T R P     |
| `PROJ-XXXXX/uat-investigation`  | 2026-01-28 | QA environment profiling        | T C       |
| `PROJ-XXXXX/prod-investigation` | 2026-01-26 | BEAM memory investigation       | T C R     |

**Legend:** T=TLDR C=Context R=Retro P=Prompt-Lab H=Handoff
```

5. **If user is searching**, highlight matching results and show context from the TLDR.

## Rules

- **Read only headers** — Don't load full file contents. First 5 lines of TLDR.md is enough for the index.
- **Sort by date** — Most recent first.
- **Fast** — This is a lookup tool. Don't analyze, just catalog.
- **Suggest pickup** — If a result looks like it has unfinished work (has `CONTEXT_FOR_NEXT_SESSION.md`), note: "Has resume context — run `/pickup` from that directory."
- Present to the user directly, don't write a file (this is a query, not an artifact).
