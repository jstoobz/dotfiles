# Retrospective & Learning Capture

Capture insights after feature completion to improve future orchestration.

## When to Offer

Offer retrospective capture when:

- Feature was complex (5+ steps)
- Issues were encountered during execution
- New patterns were discovered
- User expresses interest

## Retrospective Template

Save to `.stoobz/learnings/<ticket-id>-retro.md`:

```markdown
# Retrospective: [Ticket ID] - [Feature Name]

**Date:** [date]
**Duration:** [sessions count, e.g., "2 sessions"]

## Summary

[1-2 sentence description of what was built]

## What Went Well

- [positive observation]
- [positive observation]

## What Could Improve

- [improvement area]
- [improvement area]

## Patterns Discovered

- [reusable pattern or approach]

## Agent Performance

| Step | Agent Type      | Result | Notes                |
| ---- | --------------- | ------ | -------------------- |
| 1    | general-purpose | ✅     | Clean implementation |
| 2    | general-purpose | 🔄     | Needed 2 iterations  |
| 3    | code-reviewer   | ✅     | Caught edge case     |

## Skill Improvement Ideas

- [suggestion for feature-orchestrator skill]
- [suggestion for other skills used]

## Context for Future Work

[Notes that would help someone working on related features]
```

## Auto-Capture Data

During orchestration, track:

- Steps completed vs planned
- Review pass/fail rates
- Agent spawn count per step
- Checkpoint approvals vs rejections

## Aggregation

Periodically review `.stoobz/learnings/*.md` to identify:

- Common failure patterns → update skill guidance
- Successful patterns → add to examples
- Skill gaps → create new skills or references
