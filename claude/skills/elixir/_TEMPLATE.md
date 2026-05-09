# Elixir Skill Template

Canonical SKILL.md shape for all skills under `claude/skills/elixir/`. Copy the block below for new skills. Keep section order fixed — skip optional sections, never reorder.

See `.stoobz/skill-template.md` (decision record) and `.stoobz/elixir-skills-recon.md` (recon that informed this design) for rationale.

---

## Conventions

- **Section order is fixed.** Skip optional sections, but never reorder.
- **Decision trees** use `## Decision Tree: <Topic>` prefix and ASCII tree-shaped layout. The strongest trees ask "where does X belong?" or "what's the scope of X?" — scope-based questions force concrete answers rooted in system boundaries. Taxonomy trees ("what kind of X?") are still useful but derivative.
- **All code examples** use `MyApp` / `MyAppWeb` namespace.
- **Anti-patterns** show *wrong code that looks right* — paired with reasoning + correct alternative.
- **Common Gotchas** show *correct code with surprising behavior* — kept separate from anti-patterns intentionally.
- **Cross-skill references go inline.** When a code example uses concepts from another skill's domain, drop a parenthetical pointer like `(see ecto-expert for changeset patterns)` next to the code that needs it. The "When to Load Deeper References" section is for *within-skill* depth, not *cross-skill* pointers.
- **`targets:` frontmatter** pins versions so stale skills surface in future audits. Bump when the floor moves. Use semver-ish strings (`"1.18+"`) when you can pin precisely; use prose (`"matches selected nerves_system_* (commonly 26+)"`) when ecosystem support is genuinely variable. Honest prose beats misleading semver.

---

## Template (copy from here)

````markdown
---
name: {{skill-name}}-expert
description: {{One-line, third-person, names the surface area and what kind of decisions this skill helps with}}
targets:
  elixir: "1.18+"
  {{framework}}: "X.Y+"
  otp: "27+"
---

# {{Skill Name}} Expert

## When to Use This Skill

<!-- 3-5 explicit triggers. Concrete signals, not vague topics. This is the first filter — Claude self-selects the skill before loading deeper context. -->

- {{Concrete signal 1}}
- {{Concrete signal 2}}
- {{Concrete signal 3}}
- **Strongly recommended — negative trigger:** "Skip this skill when... (use `{{sibling-expert}}`)" — explicit exclusion prevents Claude from loading the wrong skill in crowded ecosystems (Phoenix/LiveView, Ecto/Commanded, etc.)

## Mental Model

<!-- OPTIONAL — include only when the paradigm differs from Elixir defaults. Warranted: BEAM (process model), Commanded (CQRS), LiveView (server-rendered stateful UI), Nerves (host vs target). Skip for utility skills (Ecto, Oban, Mox). -->

- {{The load-bearing concept}}
- {{What's different from "regular" Elixir code}}
- {{The failure mode this paradigm prevents}}

## Architecture / Request Flow

<!-- OPTIONAL — include only when there's a flow worth diagramming. Warranted: Phoenix, Absinthe, Commanded, Broadway. Skip for libraries (Ecto, Oban, Mox). -->

```
{{ASCII flow diagram showing the path data takes through the system}}
```

## Decision Tree: {{Most Important Decision}}

<!-- REQUIRED — at least one. Add 2-4 if the skill spans multiple decision axes. Each tree = one well-defined decision. -->

```
{{Question that triggers the decision}}?
├── {{Branch A condition}}? → {{Recommendation A}}
│   ├── {{Sub-branch}}? → {{Sub-recommendation}}
│   └── {{Sub-branch}}? → {{Sub-recommendation}}
├── {{Branch B condition}}? → {{Recommendation B}}
└── {{Branch C condition}}? → {{Recommendation C}}
```

## Decision Tree: {{Second Important Decision}}

```
{{...}}
```

## Core Patterns

<!-- The heart of the skill. Show idiomatic code for things people actually need to look up. Avoid trivia (don't show how to define a module). -->

### {{Pattern Name 1}}

```elixir
# Short comment explaining intent
defmodule MyApp.Example do
  # ...
end
```

**Rule:** {{One-line rule that captures the principle, if any}}

### {{Pattern Name 2}}

```elixir
{{...}}
```

## Anti-patterns

<!-- REQUIRED — explicit "don't do this" with reasoning AND the correct alternative. Anti-patterns = wrong code that looks right. -->

### Don't: {{Bad Pattern 1}}

```elixir
# BAD
{{the wrong way}}
```

**Why it bites:** {{The actual production failure mode — N+1, atom table exhaustion, race condition, etc.}}

**Instead:**

```elixir
# GOOD
{{the right way}}
```

### Don't: {{Bad Pattern 2}}

{{...}}

## Common Gotchas

<!-- REQUIRED — short bullets, version-tagged where relevant. Gotchas = correct code with surprising behavior. Different from anti-patterns. -->

- **{{Gotcha 1 name}}** — {{one-line explanation of the surprise}}
- **{{Gotcha 2 name}}** — {{one-line explanation, with `(since X.Y)` suffix if version-specific}}
- **{{Gotcha 3 name}}** — {{...}}

## Quick Reference

<!-- OPTIONAL — include only when the skill has lookup-heavy info that benefits from a compact table or list (ETS table types, Oban return values, HTTP status helpers). -->

```
{{Compact reference table or list}}
```

## When to Load Deeper References

<!-- REQUIRED — pair each reference file with a concrete trigger condition phrased as a question Claude can recognize in the user's prompt. -->

- {{Concrete scenario phrased as a question}}? → Read `references/{{file}}.md`
- {{Concrete scenario phrased as a question}}? → Read `references/{{file}}.md`
````

---

## Section reference

| # | Section | Required? | Purpose |
|---|---|---|---|
| 1 | Frontmatter (`name`, `description`, `targets`) | ✅ | Self-identification + version pin |
| 2 | When to Use This Skill | ✅ | First filter — does this skill apply? |
| 3 | Mental Model | Optional | Orient on paradigm if non-obvious |
| 4 | Architecture / Request Flow | Optional | Diagram if there's a flow worth showing |
| 5 | Decision Tree(s) | ✅ (≥1) | The strongest universal pattern across skills |
| 6 | Core Patterns | ✅ | Idiomatic code for common operations |
| 7 | Anti-patterns | ✅ | Wrong code that looks right + correct alternative |
| 8 | Common Gotchas | ✅ | Right code with surprising behavior |
| 9 | Quick Reference | Optional | Compact lookup table |
| 10 | When to Load Deeper References | ✅ | Triggered loads of `references/*.md` |

## Versioning convention

The `targets:` map uses string values (quoted because `1.8+` isn't a valid YAML number). Map structure is intentionally minimal-but-extensible — values can grow into objects later (e.g., `min:` / `max:` / `notes:`) without breaking parsers.

**Prose values are allowed** when ecosystem support is genuinely variable. For example, `nerves-expert` uses `otp: "matches selected nerves_system_* (commonly 26+)"` because OTP support depends on the chosen Nerves system package, and forcing a specific semver pin would be misleading. Honest prose beats fake precision.

Bump `targets:` when the version floor moves, and audit code samples for new idioms in the same pass.
