---
name: session-artifacts
description: Persist session Q&A exchanges and artifacts to organized local documentation. Use when having in-depth conversations that produce reusable knowledge.
---

# Session Artifacts Persistence

You are managing local documentation for an ongoing session. Follow this process to persist Q&A exchanges and their artifacts.

## When to Use This Skill

Invoke this skill when:

- User explicitly requests artifact persistence
- A Q&A exchange produces reusable documentation, code, or guides
- Building up knowledge on a specific topic across multiple exchanges

## Directory Structure

```
~/.claude/docs/<topic>/
├── SESSION_SUMMARY.md          # Index of all Q&A pairs (REQUIRED)
├── STRUCTURE.md                # Convention docs (optional)
├── NNN-<brief-description>/    # One folder per Q&A exchange
│   ├── NN-<artifact-name>.md
│   └── ...
└── _skills/                    # Related skills (optional)
```

## Process

### Step 1: Determine Topic Directory

Ask user or infer from context:

```
What topic should this be saved under?
Example: ~/.claude/docs/multi-agent-architecture/
```

If directory doesn't exist, create it with initial structure.

### Step 2: Check Existing State

Read `SESSION_SUMMARY.md` if it exists to determine:

- Next Q&A number (NNN)
- Existing structure to maintain

If no SESSION_SUMMARY.md exists, create one with the template below.

### Step 3: Create Q&A Folder

Create folder: `NNN-<kebab-case-description>/`

Naming rules:

- NNN: Three-digit zero-padded (001, 002, ...)
- Description: 2-5 words, kebab-case, describes the question focus
- Examples: `001-orchestrating-subagents`, `002-parallel-execution`

### Step 4: Write Artifacts

For each artifact produced in the exchange:

- Filename: `NN-<kebab-case-name>.md`
- NN: Two-digit zero-padded (01, 02, ...)
- Content: The actual documentation, code, guide, etc.

Common artifact types:

- `01-overview.md` - High-level summary
- `02-implementation.md` - How-to guide
- `03-examples.md` - Working code examples
- `04-reference.md` - API/config reference

### Step 5: Update SESSION_SUMMARY.md

Add entry to the Q&A Index table and create detailed section.

## Templates

### SESSION_SUMMARY.md (Initial)

```markdown
# Session: <Topic Name>

## Session Metadata

- **Started**: YYYY-MM-DD
- **Last Updated**: YYYY-MM-DD
- **Total Exchanges**: 0

---

## Q&A Index

| #   | Question | Core Answer | Artifacts |
| --- | -------- | ----------- | --------- |

---

<!-- Template for entries - copy below this line -->
```

### Q&A Entry (Add to SESSION_SUMMARY.md)

```markdown
## NNN: <Title>

### Question

> [Original question text - can be summarized if very long]

### Core Answer

[2-5 sentence summary of the key answer points]

### Artifacts

| File                                  | Description       |
| ------------------------------------- | ----------------- |
| [NN-name.md](./NNN-folder/NN-name.md) | Brief description |

---
```

### Index Table Row

```markdown
| [NNN](#nnn-title) | Brief question summary | Brief answer summary | [N files](./NNN-folder/) |
```

## Example Invocation

User: "Save this exchange about caching strategies to my docs"

You:

1. Check/create `~/.claude/docs/caching-strategies/`
2. Read existing SESSION_SUMMARY.md (or create new)
3. Determine next number (e.g., 003)
4. Create `003-redis-vs-memcached/`
5. Write artifacts: `01-comparison.md`, `02-implementation.md`
6. Update SESSION_SUMMARY.md with new entry

## Important Rules

- ALWAYS update SESSION_SUMMARY.md when adding content
- ALWAYS use zero-padded numbers for correct sorting
- NEVER overwrite existing Q&A folders (increment number instead)
- Keep Core Answer in SESSION_SUMMARY.md concise (2-5 sentences)
- Full details go in artifact files, not the summary
