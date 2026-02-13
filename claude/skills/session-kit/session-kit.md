# Session Kit

A composable set of Claude Code skills for managing session lifecycle — from starting work, through the session, to parking it and sharing results.

## Skills

### Core Artifacts

| Command       | Output                                                              | Purpose                                                                                                                                                                        |
| ------------- | ------------------------------------------------------------------- | ------------------------------------------------------------------------------------------------------------------------------------------------------------------------------ |
| `/tldr`       | `TLDR.md`                                                           | Concise session summary for sharing with engineers. Key findings, decisions, changes, open items. 2-minute read max.                                                           |
| `/relay`      | `CONTEXT_FOR_NEXT_SESSION.md`                                       | Everything Claude needs to resume in a new session. Optimized for machine consumption — paths, branch state, decisions, next steps, skills to load.                            |
| `/prompt-lab` | `PROMPT_LAB.md`                                                     | Captures your original prompt verbatim, analyzes its effectiveness, generates an optimized version, and provides coaching tips. Builds prompt engineering intuition over time. |
| `/retro`      | `RETRO.md`                                                          | Session retrospective — what went well, what took longer than expected, what to do differently. Tracks recurring patterns across sessions.                                     |
| `/handoff`    | `HANDOFF.md`                                                        | Teammate-facing write-up with full business context, evidence, recommendations, and links. No Claude artifacts — pure human-to-human communication.                            |
| `/rca`        | `INVESTIGATION_SUMMARY.md`, `INVESTIGATION_CONTEXT.md`, `evidence/` | Root cause analysis package — quick-scan summary + Claude-droppable deep context + raw evidence. Designed for engineer + Claude consumption without any skill setup.           |

### Lifecycle Commands

| Command                | Output                                                            | Purpose                                                                                                                        |
| ---------------------- | ----------------------------------------------------------------- | ------------------------------------------------------------------------------------------------------------------------------ |
| `/park`                | All of: `TLDR.md`, `CONTEXT_FOR_NEXT_SESSION.md`, `PROMPT_LAB.md` | "I'm stepping away." Generates all core artifacts, archives them to `~/.stoobz/<project>/<date-label>/`, updates manifest.     |
| `/park <label>`        | _(same as /park)_                                                 | Park with an explicit label for the archive directory (e.g., `/park ENG-23100`).                                               |
| `/park --archive-system` | _(scans and archives)_                                          | Retroactive cleanup — finds scattered artifacts across repos and archives them to `~/.stoobz/`.                                |
| `/persist`             | `<name>.md` in `~/.stoobz/<project>/`                             | "Save this thing." Persists a reference artifact mid-session with tags for `/index` discovery.                                 |
| `/persist <name>`      | `<name>.md` in `~/.stoobz/<project>/`                             | Persist with explicit name. Add tags after: `/persist runbook playbook tailscale`.                                              |
| `/pickup`              | _(reads existing artifacts)_                                      | "I'm back." Loads prior session context and presents a briefing. The complement to `/park`.                                    |
| `/index`               | _(displayed, not written)_                                        | "Where was that?" Reads `~/.stoobz/manifest.json` for fast lookup. Supports filtering by topic, tag, or project.              |
| `/index <filter>`      | _(displayed, not written)_                                        | Filter sessions — searches tags, summary, label, project, and branch (case-insensitive).                                      |
| `/index --deep <term>` | _(displayed, not written)_                                        | Deep search — greps inside archived artifact content when manifest metadata isn't enough.                                      |

## Session Lifecycle

```
Start                         During                        End
  |                             |                            |
  v                             v                            v
/pickup                    /tldr (anytime)              /park
  Read artifacts              Quick summary               Generates:
  Load skills                 for sharing                   TLDR.md
  Present briefing                                          CONTEXT_FOR_NEXT_SESSION.md
                           /handoff (anytime)                PROMPT_LAB.md
                              Full write-up               Archives to:
                              for teammates                 ~/.stoobz/<project>/<date>/
                                                          Updates manifest.json
                           /persist (anytime)
                              Save a reference            /retro (optional)
                              artifact mid-session          Process reflection
                              → ~/.stoobz/<project>/

Later
  |
  v
/index
  Fast manifest lookup
  Filter by tag/project
```

## Composability Flows

### Solo Deep Dive (investigation, profiling, architecture review)

```
Session 1:  [do work] → /park
Session 2:  /pickup → [continue] → /park
Session 3:  /pickup → [wrap up] → /park + /retro
```

### Ticket Work (Jira-driven features and bugs)

```
/ticket PROJ-XXXXX → [implement] → /park
Next session: /pickup → [finish] → /handoff + /park
```

### Sharing with Team

```
[complete investigation] → /tldr      (quick share in Slack)
                         → /handoff   (full context for PR review or pairing)
                         → /rca       (investigation package — teammate + their Claude pick it up)
```

### Production Investigation (debug → package → hand off)

```
Session 1:  [investigate] → /rca       (package findings + evidence for teammate)
                          → /park      (save your own session context too)
Teammate:   [drop INVESTIGATION_CONTEXT.md path into Claude] → review → verify → fix
```

### Prompt Improvement Loop

```
Session 1:  [work from initial prompt] → /prompt-lab
Session 2:  [paste optimized prompt from PROMPT_LAB.md] → [work] → /prompt-lab
            Compare: is the optimized prompt actually better?
```

### End of Day Dump

```
/park                    (saves context + summary + prompt analysis → archives)
/retro                   (reflect on what worked)
/handoff                 (if teammates need to pick up tomorrow)
```

### Finding Past Work

```
/index                          → see all sessions from manifest
/index elixir                   → filter by tag
/index memory leak              → filter by summary/label
/index insurance                → filter by project
cd into source_dir → /pickup    → resume that work
```

### Retroactive Cleanup

```
/park --archive-system          → scan for scattered artifacts
                                  review findings table
                                  archive to ~/.stoobz/
                                  optionally clean up originals
```

## File Existence Behavior

All artifact-generating skills check for existing files before writing:

- If the file exists, previous content is preserved under a timestamped "Previous" heading
- New content is added as the primary (top) section
- This creates a rolling history — latest first, older entries below
- Open items from previous sessions are carried forward (completed items checked off)

## Archive Convention

Session artifacts are archived to a central location for fast indexing and cross-project discovery:

```
~/.stoobz/
├── manifest.json                           ← fast index for /index
├── insurance/
│   ├── 2026-02-13-ENG-23100/
│   │   ├── TLDR.md
│   │   ├── PROMPT_LAB.md
│   │   └── RETRO.md
│   └── 2026-02-10-auth-token-refresh/
│       ├── TLDR.md
│       ├── HANDOFF.md
│       └── PROMPT_LAB.md
├── session-kit-lab/
│   └── 2026-02-13-archive-feature/
│       ├── TLDR.md
│       └── PROMPT_LAB.md
└── api-gateway/
    └── 2026-01-28-rate-limiting/
        ├── TLDR.md
        ├── INVESTIGATION_SUMMARY.md
        ├── INVESTIGATION_CONTEXT.md
        └── evidence/
```

- `CONTEXT_FOR_NEXT_SESSION.md` always stays in the source cwd (relay baton for `/pickup`)
- `manifest.json` is the single source of truth for `/index`
- Archives are organized by project, then by date-label

## Quick Reference

| I want to...                            | Use                    |
| --------------------------------------- | ---------------------- |
| Save everything before stepping away    | `/park`                |
| Park with a specific label              | `/park <label>`        |
| Resume where I left off                 | `/pickup`              |
| Share a quick summary                   | `/tldr`                |
| Write up findings for the team          | `/handoff`             |
| Save context for my next session        | `/relay`               |
| Improve my prompting                    | `/prompt-lab`          |
| Reflect on my process                   | `/retro`               |
| Package an investigation for a teammate | `/rca`                 |
| Find a past session                     | `/index`               |
| Save a reference artifact mid-session   | `/persist`             |
| Persist with name and tags              | `/persist <name> <tags>` |
| Find sessions by topic                  | `/index <filter>`      |
| Search inside archived artifacts        | `/index --deep <term>` |
| Archive scattered artifacts             | `/park --archive-system` |
