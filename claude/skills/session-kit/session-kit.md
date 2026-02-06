# Session Kit

A composable set of Claude Code skills for managing session lifecycle — from starting work, through the session, to parking it and sharing results.

## Skills

### Core Artifacts

| Command       | Output                        | Purpose                                                                                                                                                                        |
| ------------- | ----------------------------- | ------------------------------------------------------------------------------------------------------------------------------------------------------------------------------ |
| `/tldr`       | `TLDR.md`                     | Concise session summary for sharing with engineers. Key findings, decisions, changes, open items. 2-minute read max.                                                           |
| `/relay`      | `CONTEXT_FOR_NEXT_SESSION.md` | Everything Claude needs to resume in a new session. Optimized for machine consumption — paths, branch state, decisions, next steps, skills to load.                            |
| `/prompt-lab` | `PROMPT_LAB.md`               | Captures your original prompt verbatim, analyzes its effectiveness, generates an optimized version, and provides coaching tips. Builds prompt engineering intuition over time. |
| `/retro`      | `RETRO.md`                    | Session retrospective — what went well, what took longer than expected, what to do differently. Tracks recurring patterns across sessions.                                     |
| `/handoff`    | `HANDOFF.md`                  | Teammate-facing write-up with full business context, evidence, recommendations, and links. No Claude artifacts — pure human-to-human communication.                            |

### Lifecycle Commands

| Command   | Output                                                            | Purpose                                                                                               |
| --------- | ----------------------------------------------------------------- | ----------------------------------------------------------------------------------------------------- |
| `/park`   | All of: `TLDR.md`, `CONTEXT_FOR_NEXT_SESSION.md`, `PROMPT_LAB.md` | "I'm stepping away." Generates all core artifacts in one shot.                                        |
| `/pickup` | _(reads existing artifacts)_                                      | "I'm back." Loads prior session context and presents a briefing. The complement to `/park`.           |
| `/index`  | _(displayed, not written)_                                        | "Where was that?" Scans `.stoobz/` directories for session artifacts and builds a searchable catalog. |

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
                              Full write-up
                              for teammates              /retro (optional)
                                                            Process reflection
Later
  |
  v
/index
  Find past sessions
  across .stoobz/ dirs
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
/ticket ENG-XXXXX → [implement] → /park
Next session: /pickup → [finish] → /handoff + /park
```

### Sharing with Team

```
[complete investigation] → /tldr      (quick share in Slack)
                         → /handoff   (full context for PR review or pairing)
```

### Prompt Improvement Loop

```
Session 1:  [work from initial prompt] → /prompt-lab
Session 2:  [paste optimized prompt from PROMPT_LAB.md] → [work] → /prompt-lab
            Compare: is the optimized prompt actually better?
```

### End of Day Dump

```
/park                    (saves context + summary + prompt analysis)
/retro                   (reflect on what worked)
/handoff                 (if teammates need to pick up tomorrow)
```

### Finding Past Work

```
/index                          → see all sessions with artifacts
/index memory leak              → filter to matching sessions
cd into a result dir → /pickup  → resume that work
```

## File Existence Behavior

All artifact-generating skills check for existing files before writing:

- If the file exists, previous content is preserved under a timestamped "Previous" heading
- New content is added as the primary (top) section
- This creates a rolling history — latest first, older entries below
- Open items from previous sessions are carried forward (completed items checked off)

## Artifact Directory Convention

Artifacts live in the current working directory. The existing `.stoobz/<topic>/` convention is the natural home:

```
.stoobz/
├── ENG-22456/
│   └── uat-investigation/
│       ├── TLDR.md
│       ├── CONTEXT_FOR_NEXT_SESSION.md
│       ├── PROMPT_LAB.md
│       ├── RETRO.md
│       └── ... other work files
├── memory-leaks/
│   ├── TLDR.md
│   ├── HANDOFF.md
│   └── ... investigation files
└── ENG-BLUNT-ANALYSIS/
    └── TLDR.md
```

No special directory structure required. Artifacts coexist with other session files.

## Quick Reference

| I want to...                         | Use           |
| ------------------------------------ | ------------- |
| Save everything before stepping away | `/park`       |
| Resume where I left off              | `/pickup`     |
| Share a quick summary                | `/tldr`       |
| Write up findings for the team       | `/handoff`    |
| Save context for my next session     | `/relay`      |
| Improve my prompting                 | `/prompt-lab` |
| Reflect on my process                | `/retro`      |
| Find a past session                  | `/index`      |
