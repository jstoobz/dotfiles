# Phase 1: Context Loading

Load ticket and codebase context before planning.

## Steps

1. **Load Jira ticket**

   ```
   /ticket <TICKET-ID>
   ```

   This retrieves: title, description, acceptance criteria, parent epic, linked issues.

2. **Load linked documentation** (if any)
   - Confluence pages linked in ticket
   - Design docs or spike documents
   - Use Atlassian MCP tools to fetch

3. **Quick codebase orientation** (optional)
   - Only if unfamiliar with the area
   - Spawn an Explore agent, don't explore yourself:
   ```
   Task tool:
     subagent_type: "Explore"
     prompt: "Find files related to [feature area]. List key files and patterns."
   ```

## Output

Summarize loaded context for user:

```markdown
## Context Loaded

**Ticket:** PROJ-12345 - [Title]
**Epic:** PROJ-12300 - [Epic Title]
**Linked Docs:** [list or none]

**Key Points:**

- [bullet from description]
- [bullet from acceptance criteria]

**Ready to proceed to planning?**
```

## Transition

When user confirms, read [phase-2-planning.md](phase-2-planning.md).
