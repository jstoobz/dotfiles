---
name: park
description: Park the current session by generating all session artifacts at once — TLDR, context for next session, and prompt lab. Use when the user says "/park", "park this session", "wrap up", "I'm done for now", "save everything", or wants to create a complete handoff package before leaving a session. Runs /tldr, /relay, and /prompt-lab in sequence.
---

# Park Session

Generate all session artifacts in one pass. The "I'm stepping away, save everything" command.

## Process

1. **Announce** — Tell the user: "Parking this session. Generating artifacts..."

2. **Run each skill in sequence:**
   - `/tldr` → `TLDR.md` — Shareable session summary
   - `/relay` → `CONTEXT_FOR_NEXT_SESSION.md` — Resume context for next session
   - `/prompt-lab` → `PROMPT_LAB.md` — Original + optimized prompt

3. **For each skill, follow its full process** including:
   - Checking for existing files (merge, don't overwrite)
   - Using the correct output format from each skill's spec
   - Applying each skill's rules

4. **Summary** — After all artifacts are written, print:

```
Session parked. Artifacts in {cwd}:
  TLDR.md                       — share with the team
  CONTEXT_FOR_NEXT_SESSION.md   — paste into next session
  PROMPT_LAB.md                 — review your prompt craft
```

## Rules

- **All or nothing** — Generate all three. For individual artifacts, use the specific skill.
- **Same directory** — All artifacts go in the current working directory.
- **Respect existing files** — Each skill handles its own file existence check.
- **Don't re-explain** — Just execute. The user wants results, not descriptions.
- **No questions** — Generate all three without asking. Use best judgment for content.
