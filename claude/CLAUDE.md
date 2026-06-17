# Global — Claude Code Preferences

## Communication

- Be concise — no filler, no pleasantries, no preamble
- Lead with the answer or action, then explain if needed
- Use tables for comparisons, code blocks for examples

## First Principles

Terse heuristics to keep at the forefront while problem-solving and building. Analogies are high-density context — a 30-character moniker carries what three paragraphs would.

- **Understand before solving.** Diagnose the problem in its system's context before proposing a fix — no raw SQL at a CQRS projection, no performance fix without instrumentation. You can't fix what you don't understand; you can't fix what you can't observe. Haste to a decision matters only when the production database is already dropped.
- **Maps > mazes.** Aerial view before movement — strategic over reactive.
- **Trenches > holes.** Dig durable paths, not throwaway pits.
- **Compounds > consumes.** Prefer the decision that compounds over the one that consumes the day.
- **Do one thing well.** Scope-specific, composable, cooperative tools over omni-tools; no functionality before a justified, in-scope need. (Full treatment in **Architectural Lens** below.)
- **Rip it and ship it.** Start, then iterate on real usage — the perfect platform never arrives. Tread carefully only at foundational layers where rework compounds.

## Architectural Lens

Each surface (function, doc, repo, skill, session) optimizes for one audience or one responsibility; composition happens between surfaces, never by mixing concerns within one. When you encounter a mixed-purpose surface, name the relevant pattern — **Diátaxis** (docs by audience), **sidecar** (repos by concern), **thin-orchestrator** (skills vs scripts), **FP pipelines** (functions by composition) — and propose the split, don't paper over it. The principle is a default, not absolutism: scope where separation is warranted is case-by-case (a small file crossing concerns is fine; a 200-line mixed-purpose script usually isn't). See the `composable-units` convention in the operator's kb for the full pattern catalog and "when not to split" nuance.

Documentation routes the same way, on **lifecycle coupling**: code is the source of truth for the system as it is; present-tense reference/how-to ships in the repo, long-lived rationale (ADRs, decisions, tradeoffs) lives in the kb and **never in a tool repo**. The repo stays present-tense; rationale earns the kb or dies in thought. Commits carry *what changed* plus only the why code can't express, not narrative; a `docs/adr/` tree is premature apparatus (and a propagating precedent) until n=2.

## Architectural & Design Discussions

When the conversation is about architecture, design tradeoffs, or non-trivial technical decisions (not implementation), shift mode:

- Lead with the principle/reasoning, then the recommendation
- Cite conventions by name (XDG, SemVer, CQRS, hexagonal, ports-and-adapters, etc.) so I can look them up
- When I draw an analogy, validate it precisely; if partially right, name the nuance rather than glossing
- Use comparison tables and decision trees for branching choices
- Include rejected alternatives and *why* — the rejection reasoning is part of the value
- Goal is durable mental models across projects, not single-project optimization
- Persist durable architectural lessons to `~/.stoobz/kb/` (ADRs, decision trees, patterns) so they outlive the session

## Knowledge Base

- `~/.stoobz/kb/` — cross-project, durable architectural knowledge (ADRs, decision trees, named patterns). **Operator-private** — never referenced by path from a shipped artifact.
- `<project>/.stoobz/` — project-local session artifacts (handoffs, in-progress work, session memory).
- From operator-private surfaces only (project memory, context loaders, files under `~/.claude/` or `~/.stoobz/kb/`), reference KB entries by path so canonical docs are loaded fresh per session. From shipped artifacts (anything in a git repo whose commits leave this machine), see **Boundaries** below — cite by name, not path.
- **Load-bearing KB entries to pull during design/planning** — named here so they surface *before* a decision, not after (patterns and decision trees have weak triggers otherwise): conventions `composable-units`, `portable-references`, `diataxis`; patterns `snapshot-immutable-runs`, `wal-for-artifacts`, `python-cli-starter`; decision trees `where-to-place-the-contract`. Read the specific file when its decision is in play — don't act on this summary alone.

## Boundaries

A reference inside a shipped artifact (skill markdown, code, README, committed doc, anything that can be cloned or shared) must **resolve for any reader who fetches it** — public URL, in-repo relative path, named convention (ADR title, RFC, named pattern), or public package coordinate. Operator-private filesystem paths fail this test: the artifact rots the moment someone else opens it. Convention: **portable-references** in the operator's kb.

### This operator's instance

- **Operator-private prefixes (blocked in shipped artifacts):** `~/.stoobz/kb/`, `~/.dotfiles/.stoobz/`
- **Public contracts (allowed):** `~/.stoobz/sessions/`, `~/.stoobz/manifest.json`, `<project>/.stoobz/`
- **Enforcement:** a pre-commit hook reads `$PORTABLE_REFS_BLOCKLIST` (colon-separated path prefixes; set in `~/.zshrc.local`) and matches three forms per entry — literal, `$HOME`-prefixed, `~/`-prefixed. The hook self-no-ops when the env var is unset, or inside repos whose toplevel sits under a blocked prefix.
- **Installation:** `init.templateDir = ~/.dotfiles/git/template` auto-installs the hook into every repo created via `git init` or `git clone`. Retrofit existing repos with `install-portable-refs-hook` (lives in `~/.dotfiles/bin/`, symlinked into `~/.local/bin/`; idempotent; `--help` for usage).
- **Known limitation:** git hooks inherit the env of the process invoking `git commit`. IDE / GUI clients launched without shell init don't see `$PORTABLE_REFS_BLOCKLIST` and bypass enforcement. Accepted — the operator's commit path is overwhelmingly terminal-from-Claude-Code.

When scaffolding a new repo on this machine, or first working in a repo that predates this framework, run `install-portable-refs-hook` to confirm the hook is in place (idempotent; safe everywhere).

## Language Conventions

Language-specific conventions live in `{lang}-expert` skills (e.g., `elixir-expert`, `ecto-expert`). Load the relevant skill when working in that language.

## General Code Style

- No unnecessary comments, @doc, or @moduledoc — add only when logic isn't self-evident
- Small focused functions over long imperative blocks
- Don't add error handling for scenarios that can't happen

## Workflow

- Run tests after changes when a test suite exists
- Run the project formatter before suggesting commits
- Check for available skills before starting complex multi-step tasks

## Session Artifacts

- Session artifacts go in `.stoobz/` directories
- Use /park to wrap up sessions, /pickup to resume
