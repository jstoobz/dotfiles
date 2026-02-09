# Dotfiles — Claude Code Configuration

This is a **public repository**. All content must be 100% generic and non-proprietary.

## Rules

### No Work-Specific Content

- **NEVER** include company names, project names, internal module names, database names, or proprietary references
- **NEVER** include real credentials, API keys, connection strings, or internal URLs
- Examples must use generic placeholders: `MyApp`, `my_app_dev`, `SomeServer`, `lib/my_app/`
- Open-source library names (Commanded, Oban, Phoenix, etc.) are fine — they're public
- When in doubt, use `MyApp` or `Stoobz` as the example namespace

### Skill Separation

- **Generic skills** live here in `~/dotfiles/claude/skills/` (grouped by domain)
- **Work-specific skills** live directly in `~/.claude/skills/` (NOT symlinked from dotfiles)
- The `link-skills.sh` script only links dotfiles skills — work-specific skills are unaffected
- If a skill needs real module names, database names, or internal paths → it belongs in `~/.claude/skills/`, not here

### Before Committing

The pre-commit hook automatically checks staged files against patterns in `.guardrails`.
If `.guardrails` doesn't exist, copy the sample and add your blocked patterns:

```bash
cp .guardrails.sample .guardrails
# Edit .guardrails — add one pattern per line (extended regex, case-insensitive)
```

The `.guardrails` file is gitignored — your patterns stay private.
