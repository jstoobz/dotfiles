# dotfiles

macOS dev environment bootstrap — Homebrew, shell, languages via `mise`,
PostgreSQL, Claude Code skills, and editor config. One command on a fresh
machine, deterministic idempotent steps after that.

## Install

```shell
curl -sL https://raw.githubusercontent.com/jstoobz/dotfiles/main/bootstrap.sh | bash
```

The bootstrap script is POSIX `sh` — it runs before anything is cloned, so it
can't assume bash. Everything under `scripts/` runs *after* the clone and is
bash.

## Commands

```shell
./install                    # Run all steps
./install --list             # List available steps
./install --from-step 3      # Resume from step N
./install --only dotfiles    # Run one step by name
./install --verify           # Check installed state (read-only)
./install --dry-run          # Preview without making changes
```

## What the installer does

| #   | Step            | What it does                                    |
| --- | --------------- | ----------------------------------------------- |
| 01  | `xcode`         | Xcode Command Line Tools                        |
| 02  | `homebrew`      | Install Homebrew, run `brew bundle`             |
| 03  | `dotfiles`      | Symlink config files into `$HOME`               |
| 04  | `git`           | Generate `.gitconfig` from template             |
| 05  | `shell`         | Zsh setup                                       |
| 06  | `mise`          | Install language runtimes from `.tool-versions` |
| 07  | `postgres`      | PostgreSQL setup                                |
| 08  | `guardrails`    | Install pre-commit hook for this repo           |
| 09  | `claude-skills` | Symlink Claude Code config and skills           |
| 10  | `editor`        | VSCodium settings and extensions                |

## Layout

```
bootstrap.sh               # POSIX entry point (pipe-to-bash target)
install                    # Step runner
lib/
  utils.sh                 # Shared: symlink(), archive_path(), colored logging
  sudo-keepalive.sh
scripts/
  01-xcode.sh  …  10-editor.sh
  verify.sh                # Read-only state check (./install --verify)
config/                    # Files that get symlinked into $HOME
  editor/  git/  iex/  misc/  mise/  nvim/  tmux/  zsh/
claude/
  settings.json  CLAUDE.md # Linked into ~/.claude/
  skills/                  # Linked into ~/.claude/skills/
  vendor/                  # Git submodules (anthropics-skills, etc.)
hooks/
  pre-commit               # Guardrails hook symlinked into .git/hooks/
Brewfile                   # brew bundle input
.guardrails.sample         # Copy to .guardrails; patterns block private content
```

## Safety

- `symlink()` in `lib/utils.sh` archives whatever's already at the destination
  (real file or stale symlink) into `~/.dotfiles_backup/<timestamp>/` before
  creating the new link. Re-running `install` never clobbers state.
- The pre-commit hook auto-formats staged files (`shfmt`, `prettier`, `ruff`)
  and greps every non-binary staged file against patterns in `.guardrails`.
  This is a public repo; the guardrails keep work-specific content out.
- `shellcheck` runs in CI against every script the installer touches.

## Adding a new config file

1. Drop the source in `config/<category>/`.
2. Add a `symlink` call to `scripts/03-dotfiles.sh`.
3. Add the same pair to `scripts/verify.sh` so drift is detectable.
