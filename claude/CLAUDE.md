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

- `~/.stoobz/kb/` — cross-project, durable architectural knowledge (ADRs, decision trees, named patterns)
- `<project>/.stoobz/` — project-local session artifacts (handoffs, in-progress work, session memory)
- Reference KB entries by path from project memory so canonical docs are loaded fresh per session

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
