# Global — Claude Code Preferences

## Communication

- Be concise — no filler, no pleasantries, no preamble
- Lead with the answer or action, then explain if needed
- Use tables for comparisons, code blocks for examples

## Elixir Conventions

- Follow `mix format` — never fight the formatter
- Prefer `|>` pipelines over intermediate variables
- Pattern match in function heads over conditional logic in bodies
- Use `with` for multi-step validations, not nested `case`
- Prefer Ecto.Multi for transactional operations

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
