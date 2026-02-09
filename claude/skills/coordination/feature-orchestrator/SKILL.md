---
name: feature-orchestrator
description: Orchestrate feature implementation through planning, agent delegation, and user checkpoints. Use when starting work on a Jira ticket or implementing a feature with structured review gates. Triggers on "implement feature", "work on ticket", "orchestrate", or ticket IDs like PROJ-12345. CRITICAL - This skill coordinates agents, it does NOT implement directly.
---

# Feature Orchestrator

Coordinate feature implementation by **delegating to agents**, not by implementing directly.

## The One Rule

**YOU ARE A COORDINATOR, NOT A WORKER.**

Never write implementation code. Never edit files directly. Your job is to:

1. Plan the work
2. Spawn agents to do the work
3. Spawn agents to review the work
4. Report progress to the user

## Phase Router

Determine current phase and read ONLY the relevant reference file:

| Phase             | Trigger                                | Read                                                      |
| ----------------- | -------------------------------------- | --------------------------------------------------------- |
| **1. Context**    | Starting fresh with ticket ID          | [phase-1-context.md](references/phase-1-context.md)       |
| **2. Planning**   | Have context, need plan                | [phase-2-planning.md](references/phase-2-planning.md)     |
| **3. Execution**  | Have approved plan, ready to implement | [phase-3-execution.md](references/phase-3-execution.md)   |
| **4. Completion** | All steps done                         | [phase-4-completion.md](references/phase-4-completion.md) |

## Quick Reference

### Spawning Implementation Agent

```
Task tool:
  subagent_type: "general-purpose"
  prompt: |
    Implement Step N: [Name]

    Goal: [from plan]
    Files: [from plan]
    Test: [from plan]

    Context: [relevant details]

    Return a summary of changes made.
```

### Spawning Code Review Agent

```
Task tool:
  subagent_type: "feature-dev:code-reviewer"
  prompt: |
    Review the implementation of Step N: [Name]

    Acceptance criteria:
    - [criterion 1]
    - [criterion 2]

    Focus on: bugs, security, code quality
```

### Session Boundary

After planning approval, if context is heavy, generate execution prompt:

```markdown
## Resume Feature Orchestration

Plan: [path to plan file]
Step: 1
Mode: per-phase

Read the plan and execute using Task agents. Never implement directly.
```

## Anti-Patterns (Never Do These)

- Writing code yourself
- Editing files with Edit/Write tools
- Reading implementation files to "understand" before delegating
- Doing "just this small thing" directly
- Running build/test commands yourself (delegate to agents)
