# Phase 2: Planning

Decompose the feature into small, testable steps with clear boundaries.

## Planning Principles

1. **Small steps** - Each step should be completable in one agent session
2. **Testable** - Each step has a verification method
3. **Independent** - Minimize cross-step dependencies where possible
4. **Checkpoints** - Mark steps where user approval adds value

## Plan Template

Create a plan file at `.stoobz/plans/<ticket-id>-plan.md`:

```markdown
# Implementation Plan: [Feature Name]

**Ticket:** [ID]
**Created:** [date]
**Checkpoint Mode:** [to be set]

## Steps

### Step 1: [Name]

- **Goal:** What this accomplishes
- **Files:** Expected files to create/modify
- **Test:** How to verify success
- **Checkpoint:** Yes/No

### Step 2: [Name]

- **BlockedBy:** Step 1 (if dependent)
- **Goal:** ...
- **Files:** ...
- **Test:** ...
- **Checkpoint:** Yes/No

[continue for all steps]

## Execution Prompt

Copy this to a new session after approval:

---

Resume feature orchestration for [TICKET-ID].

Plan: .stoobz/plans/[ticket-id]-plan.md
Start at: Step 1
Mode: [checkpoint-mode]

## Execute using Task agents. Never implement directly.
```

## Checkpoint Mode Selection

Present options to user:

| Mode           | Description                   | Best For                        |
| -------------- | ----------------------------- | ------------------------------- |
| **per-step**   | Approve after every step      | Unfamiliar code, risky changes  |
| **per-phase**  | Approve at marked checkpoints | Balanced control (recommended)  |
| **final-only** | Approve at end                | Familiar code, trusted patterns |

## Task Creation

After user approves plan, create tasks:

```
TaskCreate:
  subject: "Step 1: [Name]"
  description: "[Full step details from plan]"
  activeForm: "Implementing [name]..."
```

Set dependencies:

```
TaskUpdate:
  taskId: "2"
  addBlockedBy: ["1"]
```

## Context Check

Before proceeding to execution, evaluate context usage:

- **< 40% context used:** Continue in this session
- **> 40% context used:** Recommend new session

If recommending new session:

```markdown
## Planning Complete

Plan saved to: `.stoobz/plans/[ticket-id]-plan.md`

**Recommendation:** Start a fresh session for execution.

Copy this prompt to continue:

---

## [execution prompt from plan file]
```

## Transition

When ready to execute (same or new session), read [phase-3-execution.md](phase-3-execution.md).
