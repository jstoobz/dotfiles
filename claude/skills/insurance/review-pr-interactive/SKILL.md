---
name: review-pr-interactive
description: Use when reviewing a GitHub PR with the intent to post feedback - guides through analysis, issue identification, and staged comment approval before posting
---

# Interactive PR Review

Review a PR, identify issues with fixes, draft a comment for approval, then post only when explicitly approved.

## Workflow

```dot
digraph pr_review {
    rankdir=TB;
    "Receive PR number and repo" [shape=box];
    "Fetch PR diff and details" [shape=box];
    "Analyze changes" [shape=box];
    "List issues with fixes" [shape=box];
    "Draft review comment" [shape=box];
    "Present to user" [shape=box];
    "User approved?" [shape=diamond];
    "User requested changes?" [shape=diamond];
    "Post comment to PR" [shape=box];
    "Revise draft" [shape=box];
    "Done" [shape=doublecircle];

    "Receive PR number and repo" -> "Fetch PR diff and details";
    "Fetch PR diff and details" -> "Analyze changes";
    "Analyze changes" -> "List issues with fixes";
    "List issues with fixes" -> "Draft review comment";
    "Draft review comment" -> "Present to user";
    "Present to user" -> "User approved?";
    "User approved?" -> "Post comment to PR" [label="yes"];
    "User approved?" -> "User requested changes?" [label="no"];
    "User requested changes?" -> "Revise draft" [label="yes"];
    "User requested changes?" -> "Done" [label="no/cancel"];
    "Revise draft" -> "Present to user";
    "Post comment to PR" -> "Done";
}
```

## Required Information

Before starting, confirm you have:

- Repository in `owner/repo` format
- PR number

If not provided, ask the user.

## Analysis Output Format

Present findings in this structure:

```markdown
## PR Summary

[1-2 sentence description of what the PR does]

## Issues Found

### 1. [Issue Title]

**Location:** `file.ts:123`
**Severity:** High/Medium/Low
**Issue:** [What's wrong]
**Suggested Fix:** [How to fix it]

### 2. [Next issue...]

## Draft Review Comment

---

## [The actual comment text that would be posted]

**Review type:** Comment / Approve / Request Changes

Ready to post? Say "post it" or request modifications.
```

## Approval Triggers

Only post after explicit approval:

- "post it"
- "submit"
- "looks good, post"
- "approve and post"

## Revision Triggers

Revise the draft when user says:

- "soften the tone"
- "be more specific about..."
- "remove point X"
- "add a note about..."
- "change to request changes"

## Do NOT Post When

- User says "cancel", "nevermind", "stop"
- User hasn't explicitly approved
- User is still asking questions about the PR
- No explicit approval phrase was given

## Review Types

| Type            | When to Use                              |
| --------------- | ---------------------------------------- |
| Comment         | General feedback, questions, suggestions |
| Approve         | Code looks good, minor or no issues      |
| Request Changes | Blocking issues that must be fixed       |

Default to "Comment" unless user specifies otherwise.
