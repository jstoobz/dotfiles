# Phase 4: Completion

Wrap up the feature implementation with final review and delivery.

## Completion Checklist

### 1. Final Code Review

Spawn comprehensive review of all changes:

```
Task tool:
  subagent_type: "feature-dev:code-reviewer"
  description: "Final review all changes"
  prompt: |
    Comprehensive review of feature implementation.

    **Ticket:** [ID] - [Title]

    **All files changed:**
    [list from all step summaries]

    **Review for:**
    - Cross-step integration issues
    - Missed edge cases
    - Security vulnerabilities
    - Performance concerns
    - Code consistency

    Return detailed findings.
```

### 2. Verification

Spawn verification agent:

```
Task tool:
  subagent_type: "general-purpose"
  description: "Run verification suite"
  prompt: |
    Verify the feature implementation:

    1. Run relevant tests: [test command]
    2. Run linting/formatting: [lint command]
    3. Build the project: [build command]

    Return: PASS/FAIL with details
```

### 3. Summary for User

Present completion summary:

```markdown
## Feature Complete: [Name]

**Ticket:** [ID]

### Changes Made

| Step | Description | Files   |
| ---- | ----------- | ------- |
| 1    | [name]      | [files] |
| 2    | [name]      | [files] |
| ...  | ...         | ...     |

### Verification

- ✅ Tests: [result]
- ✅ Lint: [result]
- ✅ Build: [result]

### Final Review

[Summary of review findings, if any]

### Next Steps

1. **Commit changes?** → `/commit`
2. **Create PR?** → Will generate PR with summary
3. **Need adjustments?** → Specify what to change
```

## Commit Flow

If user wants to commit:

```
/commit
```

## PR Flow

If user wants PR:

```
Skill tool:
  skill: "commit-commands:commit-push-pr"
```

## Retrospective (Optional)

If this was a learning experience, offer to capture insights:

```markdown
### Retrospective

**What went well:**

- [observation]

**What could improve:**

- [observation]

**Save these learnings?** I can append to `.stoobz/learnings/[ticket-id].md`
```

## Retrospective

For complex features or when learning opportunities exist, offer retrospective capture.
See [retrospective.md](retrospective.md) for template and guidance.

## Session Artifacts

Files created during orchestration:

- `.stoobz/plans/[ticket-id]-plan.md` - The implementation plan
- `.stoobz/learnings/[ticket-id]-retro.md` - Retrospective (if captured)

These can be referenced in future sessions or for similar features.
