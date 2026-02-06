---
name: tool-config-backup
description: Backup and document IDE and tool configurations. Use when needing to save tool settings before changes, understand config file locations, create restore points, or document what configuration files control. Triggers on phrases like "backup DataGrip config", "save my IDE settings", "where are VS Code settings", "backup before changes", or "config backup".
---

# Tool Config Backup

Backup, document, and restore IDE and tool configurations.

## Supported Tools

| Tool          | Config Location                                                  | Key Files                                                  |
| ------------- | ---------------------------------------------------------------- | ---------------------------------------------------------- |
| DataGrip      | `~/Library/Application Support/JetBrains/DataGrip<version>/`     | `options/dataSources.xml`, `options/dataSources.local.xml` |
| IntelliJ IDEA | `~/Library/Application Support/JetBrains/IntelliJIdea<version>/` | `options/`, `keymaps/`                                     |
| VS Code       | `~/Library/Application Support/Code/User/`                       | `settings.json`, `keybindings.json`                        |
| Cursor        | `~/Library/Application Support/Cursor/User/`                     | `settings.json`, `keybindings.json`                        |
| iTerm2        | `~/Library/Preferences/`                                         | `com.googlecode.iterm2.plist`                              |
| Homebrew      | `/opt/homebrew/` or `/usr/local/`                                | `Brewfile` (generate with `brew bundle dump`)              |

## Workflow

### 1. Identify Config Files

For the requested tool, locate config files:

```bash
ls -la "<config-location>"
```

### 2. Create Timestamped Backup

```bash
TOOL="datagrip"
TIMESTAMP=$(date +%Y%m%d_%H%M%S)
BACKUP_DIR="$HOME/.config-backups/$TOOL/$TIMESTAMP"

mkdir -p "$BACKUP_DIR"
cp -r "<source-config-path>" "$BACKUP_DIR/"
```

### 3. Document Backup

Create manifest in backup directory:

```markdown
# Backup Manifest

Tool: DataGrip 2021.3
Date: 2026-02-02 09:30:00
Reason: Before regenerating data source configs

## Files Backed Up

- options/dataSources.xml (database connections)
- options/dataSources.local.xml (credentials reference)

## Restore Command

cp -r ~/.config-backups/datagrip/20260202_093000/\* \
 "~/Library/Application Support/JetBrains/DataGrip2021.3/"
```

## Tool-Specific Guides

### DataGrip

**What to backup:**

- `options/dataSources.xml` - Data source definitions (connections, drivers)
- `options/dataSources.local.xml` - Local credential references
- Project `.idea/dataSources.xml` - Project-level connections

**What controls what:**
| File | Controls |
|------|----------|
| `dataSources.xml` | Connection URLs, drivers, SSH tunnels |
| `dataSources.local.xml` | Password storage references (points to keychain) |
| `workspace.xml` | UI layout, open tabs, panel positions |

**Note:** Passwords stored in macOS Keychain, not in XML files.

### VS Code / Cursor

**What to backup:**

- `settings.json` - All editor preferences
- `keybindings.json` - Custom keyboard shortcuts
- `extensions/` - Installed extensions (or just list with `code --list-extensions`)

**Quick backup:**

```bash
code --list-extensions > extensions.txt
cp settings.json keybindings.json ~/.config-backups/vscode/
```

### JetBrains IDEs (General)

**Common locations:**

- `options/` - IDE settings, plugins, appearance
- `keymaps/` - Custom keyboard shortcuts
- `codestyles/` - Code formatting rules
- `templates/` - Live templates and file templates

## Restore Workflow

1. Close the application
2. Copy backup files to config location
3. Restart application
4. Verify settings loaded correctly

```bash
# Example restore
cp -r ~/.config-backups/datagrip/20260202_093000/options/* \
  "~/Library/Application Support/JetBrains/DataGrip2021.3/options/"
```

## Best Practices

- Always backup before making config changes
- Use descriptive reason in manifest
- Keep last 3-5 backups per tool
- Test restore on non-critical settings first
