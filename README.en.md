# claudefxxk — Claude Fingerprint Reset Toolkit

Make Claude Code CLI not recognize this machine.

**[中文版 →](README.md)**

---

## What This Is

`claudefxxk` is a set of bash scripts for macOS that:

1. **Fully isolates** — thoroughly cleans Claude Code CLI identity traces
2. **Resets fingerprint** — reinstalls CLI to generate a brand new userID
3. **Whitelist-recovers** — only restores your backed-up custom assets (skills, hooks, plugins, CLAUDE.md, etc.)

**Core Design Principles:**
- Explicit config, never silently scan `$HOME`
- Conditional execution, soft warning if tool not present, never silently skip
- Dry-run first, destructive operations print but do not execute
- Whitelist recovery, never restore anything that might carry old fingerprints

---

## What It Does

| Capability |
|------------|
| Kill all Claude / claude / claude-code processes |
| Delete `~/.claude.json` (Claude identity file) |
| Delete Claude credentials from Keychain |
| Clean claude-code from npm cache |
| Remove `~/.config/Claude` and Desktop App |
| Clean browser Claude data (optional) |
| Clean shell history (optional) |
| Reinstall Claude Code CLI (optional) |
| Whitelist-restore your skills / hooks / plugins / CLAUDE.md |
| Compare old vs new userID to confirm reset |

---

## What It Does NOT Do

| What It Does NOT Do | Note |
|---------------------|------|
| **Will NOT delete your source code** | Only cleans Claude traces, never touches your project code |
| **Will NOT delete git repositories** | Never touches any `.git/` directory |
| **Will NOT modify system configs** | Only modifies optional git email and `.zshrc` proxy marker |
| **Will NOT scan entire `$HOME`** | Only cleans explicitly configured `CLEAN_ROOTS` |
| **Will NOT kill MMS main process** | Only terminates Claude child processes under MMS |
| **Does NOT bypass platform risk controls** | This is a dev/debug tool, not a ToS circumvention product |
| **Will NOT auto-login to Claude** | Manual OAuth required after reinstall |

---

## What NOT to Do

1. **Never run inside an MMS / Claude CLI session**
   - The script detects `$HOME` virtualization and exits if run inside MMS
   - Run in native Terminal / iTerm2 instead

2. **Never skip dry-run**
   - Always run `DRY_RUN=1` first to see what it will do

3. **Never run without backing up**
   - Run `backup-missing-to-safe-zone.sh` first and verify the output

4. **Do not expect a "one-click unban"**
   - This is a dev/debug tool, not a platform circumvention product

---

## Customization Checklist — Review Before Use

The following configs are **strongly recommended** to review before use. Ask your LLM to check them if unsure.

### 1. `~/.config/claudefxxk/config.sh` — Path Config

```bash
CLEAN_ROOTS=(
    "$HOME/your-project-a"
    "$HOME/your-project-b"
)
```

**Double-check**: These directories actually contain `.claude/` traces you want to clean, and contain no accidental paths. `CLEAN_ROOTS` defaults to empty — if not configured, no project-level `.claude` cleanup will occur.

### 2. `templates/settings.json` — statusLine Path

```json
"statusLine": {
  "type": "command",
  "command": "/bin/bash -c 'echo \"[Claude] $(date +%H:%M:%S) | $(whoami)@$(hostname -s)\"'"
}
```

This is a generic fallback. Replace with your own `statusline-command.sh` path after recovery if needed.

### 3. MCP Server Config

Projects in `MCP_PROJECTS` are scanned for `mcp.json`. Ensure these files do not contain sensitive credentials (API keys, tokens).

### 4. Permissions (permissions.allow / deny)

The default config allows a broad set of bash commands. Review the `permissions` field in `templates/settings.json` if your environment has special security requirements.

---

## Dry-Run Mode Explained

### How to Run

```bash
DRY_RUN=1 ./scripts/claude-nuke-and-restore.sh
```

### What Dry-Run Does

- Prints all destructive commands (`rm`, `pkill`, `cp`, etc.) with `[DRY-RUN]` prefix
- Runs harmless read-only checks (`pgrep`, `git status`, `ls`, `python3`, etc.)
- Shows exactly which paths will be accessed and cleaned

### What Dry-Run Does NOT Do

- **Does NOT execute any file deletion** (rm is only printed)
- **Does NOT kill any process** (pkill is only printed)
- **Does NOT modify .zshrc** (awk is only printed)
- **Does NOT actually copy any file**

### Dry-Run Safety Boundaries

Dry-run still performs the following **read-only** operations, which do not affect your files:

| Operation | Note |
|-----------|------|
| `pgrep -x "claude"` | Read-only process query |
| `git status --short` | Read-only git status |
| `ls -dt ...` | Read-only directory listing |
| `python3 -c "json.load(...)"` | Read-only JSON parsing |
| `security dump-keychain` | Read-only keychain query (no deletion) |
| `read -p "..."` | Interactive prompt (you can Ctrl-C anytime) |

If you want to avoid even these read-only operations, manually comment out the relevant lines after reading the script.

---

## Execution Guide

### Step 0: Clone

```bash
git clone git@github.com:CtriXin/claudefxxk.git
cd claudefxxk
```

### Step 1: Configuration

```bash
mkdir -p ~/.config/claudefxxk
cat > ~/.config/claudefxxk/config.sh << 'EOF'
# For git dirty check
SCAN_ROOTS=(
    "$HOME/your-project-a"
    "$HOME/your-project-b"
)

# For project-level .claude cleanup (default empty, scans nothing)
CLEAN_ROOTS=(
    "$HOME/your-project-a"
    "$HOME/your-project-b"
)

# MCP server project directories
MCP_PROJECTS=(
    "$HOME/your-project-a"
)
EOF
```

### Step 2: Backup Assets

```bash
./scripts/backup-missing-to-safe-zone.sh
```

Outputs to `~/claude_safe_zone/backup-run-YYYYMMDD-HHMMSS/`. Verify it contains hooks/, skills-entity/, CLAUDE.md, etc.

### Step 3: Dry-Run Test

```bash
DRY_RUN=1 ./scripts/claude-nuke-and-restore.sh
```

Prints all 18 phases' commands but **does NOT actually delete anything**.

### Step 4: Execute

```bash
./scripts/claude-nuke-and-restore.sh
```

Follow prompts. Key decision points:
- Phase 0: API key handled? Repos pushed?
- Phase 1: MMS work saved? (if MMS is running)
- Phase 8: first lightly clear the active Chrome profile's `Local Storage / Session Storage`, then decide whether to deep-delete `IndexedDB / Cookie DB` after you confirm Chrome has been safely closed
- Phase 15: npm reinstall?
- Phase 16: Automatic old vs new userID comparison

### Step 5: Install Proxy (Optional)

```bash
./scripts/setup-proxy.sh
source ~/.zshrc
```

---

## Directory Structure

```
.
├── scripts/
│   ├── claude-nuke-and-restore.sh      # Main script (18 phases)
│   ├── backup-missing-to-safe-zone.sh  # Asset backup + sanitize
│   └── setup-proxy.sh                  # Proxy installer
├── templates/
│   ├── settings.json                   # Generic settings template
│   └── mcp.json                        # Empty MCP template
├── docs/
│   ├── EXECUTE.md                      # Execution manual
│   └── review-notes.md                 # Design decisions
├── .ai/
│   └── agent-release-notes.md          # Release notes
├── LICENSE                             # MIT
└── README.en.md                        # This document (English)
```

---

## System Requirements

- macOS
- bash 3.2+ (macOS default)
- python3
- npm (for reinstalling Claude Code CLI)

---

## Disclaimer

This project is for educational and development debugging purposes only. Users bear full responsibility for any consequences. This project does not guarantee bypassing any platform risk controls and does not encourage violating any terms of service.

---

## License

MIT

---

**[中文版 →](README.md)**
