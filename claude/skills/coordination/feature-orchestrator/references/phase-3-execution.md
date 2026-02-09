# Phase 3: Execution

Execute the plan by spawning agents. **Never implement directly.**

## The Execution Loop

For each step in order:

### 1. Mark In Progress

```
TaskUpdate:
  taskId: "[step-task-id]"
  status: "in_progress"
```

### 2. Spawn Implementation Agent

```
Task tool:
  subagent_type: "general-purpose"
  description: "Implement step N"
  prompt: |
    ## Task: Implement Step N - [Name]

    **Goal:** [from plan]

    **Files to create/modify:**
    - [file 1]
    - [file 2]

    **Verification:** [test criteria]

    **Context:**
    [Any relevant context from planning phase]

    **Instructions:**
    1. Implement the goal
    2. Run verification to confirm it works
    3. Return a summary of:
       - Files changed
       - What was implemented
       - Verification results
```

### 3. Spawn Code Review Agent

After implementation agent returns:

```
Task tool:
  subagent_type: "feature-dev:code-reviewer"
  description: "Review step N"
  prompt: |
    Review the implementation of Step N: [Name]

    **Files changed:** [from implementation summary]

    **Acceptance criteria:**
    - [criterion 1]
    - [criterion 2]

    **Check for:**
    - Bugs and logic errors
    - Security vulnerabilities
    - Code quality issues
    - Adherence to project patterns

    Return: PASS or FAIL with specific issues
```

### 4. Handle Review Result

**If PASS:**

- If checkpoint step: Present to user (see Checkpoint Template below)
- If not checkpoint: Continue to next step

**If FAIL:**

- Spawn fix agent with specific issues
- Re-review after fix
- Loop until pass

### 5. Mark Complete

```
TaskUpdate:
  taskId: "[step-task-id]"
  status: "completed"
```

### 6. Continue

Move to next unblocked task.

## Checkpoint Template

When reaching a checkpoint step:

```markdown
## Checkpoint: Step N Complete

### Summary

[What the agent implemented]

### Files Changed

- `path/to/file` - [change description]

### Review Results

- ✅ [passed criteria]
- ⚠️ [any notes]

### Next Step

Step N+1: [Name] - [brief description]

**Options:**

1. ✅ Approve and continue
2. 🔄 Request changes
3. ⏸️ Pause (resume later)
4. ❌ Abort
```

## Parallel Steps

If multiple steps have no dependencies between them, spawn agents in parallel:

```
[Single message with multiple Task tool calls]

Task tool:
  subagent_type: "general-purpose"
  description: "Implement step 3"
  prompt: [step 3 details]

Task tool:
  subagent_type: "general-purpose"
  description: "Implement step 4"
  prompt: [step 4 details]
```

## Error Recovery

If an agent fails or produces errors:

1. Capture the error output
2. Spawn a debug agent:
   ```
   Task tool:
     subagent_type: "general-purpose"
     prompt: |
       Debug and fix: [error description]
       Context: [what was attempted]
       Return: fixed implementation
   ```
3. Re-run review after fix

## Transition

When all steps complete, read [phase-4-completion.md](phase-4-completion.md).
