# Global — Claude Code Preferences

## Communication

- Be concise — no filler, no pleasantries, no preamble
- Lead with the answer or action, then explain if needed
- Use tables for comparisons, code blocks for examples

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
