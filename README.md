# claudefxxk — Claude 指纹重置工具

**English**: A macOS toolkit to make Claude Code CLI "not recognize" your machine — by fully isolating and resetting identity fingerprints.

---

## 这是什么 / What This Is

`claudefxxk` 是一组 bash 脚本，用于在 macOS 上彻底清理 Claude Code CLI 的身份痕迹，然后重新安装 CLI 并白名单恢复你的自定义资产（skills、hooks、plugins、CLAUDE.md 等）。

`claudefxxk` is a set of bash scripts for macOS that thoroughly cleans Claude Code CLI identity traces, reinstalls the CLI, and whitelist-restores your custom assets (skills, hooks, plugins, CLAUDE.md, etc.).

**核心设计原则 / Core Design Principles:**
- **显式配置，绝不静默扫描 $HOME** / Explicit config, never silently scan `$HOME`
- **条件执行，不存在则 soft warning** / Conditional execution, soft warning if not present
- **Dry-Run 先行** / Dry-run first
- **白名单恢复** / Whitelist recovery only

---

## 它会做什么 / What It Does

| 能力 | Capability |
|------|-----------|
| 终止所有 Claude / claude / claude-code 进程 | Kill all Claude / claude / claude-code processes |
| 删除 `~/.claude.json`（Claude 身份文件） | Delete `~/.claude.json` (Claude identity file) |
| 删除 Keychain 中的 Claude 凭证 | Delete Claude credentials from Keychain |
| 清理 npm cache 中的 claude-code | Clean claude-code from npm cache |
| 删除 `~/.config/Claude` 和 Desktop App | Remove `~/.config/Claude` and Desktop App |
| 清理浏览器中的 Claude 相关数据（可选） | Clean browser Claude data (optional) |
| 清理 shell history 中的 claude 记录（可选） | Clean shell history (optional) |
| 重新安装 Claude Code CLI（可选） | Reinstall Claude Code CLI (optional) |
| 白名单恢复你的 skills / hooks / plugins / CLAUDE.md | Whitelist-restore your skills / hooks / plugins / CLAUDE.md |
| 对比新旧 userID，确认身份已重置 | Compare old vs new userID to confirm reset |

---

## 它不会做什么 / What It Does NOT Do

| 不会做的事 | What It Does NOT Do |
|------------|---------------------|
| **不会删除你的代码文件** | **Will NOT delete your source code** |
| **不会删除 git repository** | **Will NOT delete git repositories** |
| **不会修改系统级配置**（除了可选的 git email 和 .zshrc proxy marker） | **Will NOT modify system configs** (except optional git email and .zshrc proxy marker) |
| **不会扫描整个 `$HOME` 目录**（只清理你显式配置的 `CLEAN_ROOTS`） | **Will NOT scan entire `$HOME`** (only cleans explicitly configured `CLEAN_ROOTS`) |
| **不会删除 MMS 主进程或配置**（只终止 MMS 下的 Claude 子进程） | **Will NOT kill MMS main process or config** (only terminates Claude child processes under MMS) |
| **不保证 100% 绕过任何平台风控或账号限制** | **Does NOT guarantee bypassing any platform risk controls or account restrictions** |
| **不会自动帮你登录 Claude 账号**（重装后需手动 OAuth） | **Will NOT auto-login to Claude** (manual OAuth required after reinstall) |

---

## 不建议做的事情 / What NOT to Do

1. **不要在 MMS / Claude CLI session 内运行主脚本**
   - 脚本会检测 `$HOME` 虚拟化，如果在 MMS 内会直接退出
   - 请在系统原生 Terminal / iTerm2 中运行
   - **Never run inside an MMS / Claude CLI session** — the script detects `$HOME` virtualization and exits

2. **不要跳过 Dry-Run**
   - 首次使用前务必先 `DRY_RUN=1` 跑一次，确认它要做什么
   - **Never skip dry-run on first use**

3. **不要在没有备份的情况下运行**
   - 先运行 `backup-missing-to-safe-zone.sh`，确认你的资产已备份
   - **Never run without backing up first**

4. **不要期望这是"一键解封"**
   - 这是一个开发/调试工具，不是绕过平台规则的产品
   - **This is a dev/debug tool, not a platform circumvention product**

---

## 建议自己修改或让 LLM 再检查的部分 / Customization Checklist

以下配置强烈建议你在使用前仔细检查，必要时让 LLM 帮你 review：

The following configs are **strongly recommended** to review before use. Ask your LLM to check them if unsure.

### 1. `~/.config/claudefxxk/config.sh` — 路径配置

```bash
# 你要清理的项目目录（phase 10 会删除其中的 .claude/sessions 等）
CLEAN_ROOTS=(
    "$HOME/your-project-a"
    "$HOME/your-project-b"
)
```

**务必确认**: 这些目录确实包含你想要清理的 `.claude/` 痕迹，且没有放错路径。

**Double-check**: These directories actually contain `.claude/` traces you want to clean, and no accidental paths.

### 2. `templates/settings.json` — statusLine 路径

```json
"statusLine": {
  "type": "command",
  "command": "/bin/bash -c 'echo \"[Claude] $(date +%H:%M:%S) | $(whoami)@$(hostname -s)\"'"
}
```

这是一个通用 fallback。如果你有自己的 `statusline-command.sh`，请在恢复后手动替换这个路径。

Replace this with your own `statusline-command.sh` path after recovery if needed.

### 3. MCP server 配置

`MCP_PROJECTS` 中的项目会被扫描 `mcp.json`。请确认这些项目的 `mcp.json` 不包含敏感凭证（如 API key）。

Ensure `mcp.json` files in `MCP_PROJECTS` do not contain sensitive credentials.

### 4. 权限配置（permissions.allow / deny）

默认配置允许较广泛的 bash 命令。如果你所在环境有特殊安全要求，请让 LLM 帮你审查 `templates/settings.json` 中的 `permissions` 字段。

Review the `permissions` field in `templates/settings.json` if your environment has special security requirements.

---

## 执行步骤 / Execution Guide

### Step 0: 克隆 / Clone

```bash
git clone git@github.com:CtriXin/claudefxxk.git
cd claudefxxk
```

### Step 1: 配置 / Configuration

```bash
mkdir -p ~/.config/claudefxxk
cat > ~/.config/claudefxxk/config.sh << 'EOF'
# 用于 git dirty 检查 / For git dirty check
SCAN_ROOTS=(
    "$HOME/your-project-a"
    "$HOME/your-project-b"
)

# 用于项目级 .claude 清理 / For project-level .claude cleanup
# 默认空数组，不扫描任何目录 / Default empty, scans nothing
CLEAN_ROOTS=(
    "$HOME/your-project-a"
    "$HOME/your-project-b"
)

# MCP server 项目目录 / MCP server project directories
MCP_PROJECTS=(
    "$HOME/your-project-a"
)
EOF
```

### Step 2: 备份资产 / Backup Assets

```bash
./scripts/backup-missing-to-safe-zone.sh
```

输出到 `~/claude_safe_zone/backup-run-YYYYMMDD-HHMMSS/`。确认包含 hooks/、skills-entity/、CLAUDE.md 等。

Outputs to `~/claude_safe_zone/backup-run-YYYYMMDD-HHMMSS/`. Verify it contains hooks/, skills-entity/, CLAUDE.md, etc.

### Step 3: Dry-Run 测试 / Dry-Run Test

```bash
DRY_RUN=1 ./scripts/claude-nuke-and-restore.sh
```

这会打印所有 18 个阶段将要执行的命令，但**不会实际删除任何文件**。

This prints all 18 phases' commands but **does NOT actually delete anything**.

### Step 4: 正式执行 / Execute

```bash
./scripts/claude-nuke-and-restore.sh
```

按提示逐步确认。关键决策点：
- Phase 0: API key 已处理？repo 已 push？
- Phase 1: MMS 工作已保存？（如果运行中）
- Phase 8: Chrome 处理（s=跳过, k=自动关闭, 回车=确认）
- Phase 15: 是否 npm 重新安装
- Phase 16: 自动对比新旧 userID

Follow prompts. Key decisions: API key handled, repos pushed, MMS work saved, Chrome handling, npm reinstall, userID comparison.

### Step 5: 安装代理（可选）/ Install Proxy (Optional)

```bash
./scripts/setup-proxy.sh
source ~/.zshrc
```

---

## Dry-Run 模式详解 / Dry-Run Mode Explained

### 怎么跑 / How to Run

```bash
DRY_RUN=1 ./scripts/claude-nuke-and-restore.sh
```

### Dry-Run 会做什么 / What Dry-Run Does

- 打印所有 `rm`、`pkill`、`cp` 等 destructive 命令（前缀 `[DRY-RUN]`）
- 运行无害的只读检查（`pgrep`、`git status`、`ls`、`python3 -c` 等）
- 让你看到脚本会访问哪些路径、清理哪些文件

- Prints all destructive commands with `[DRY-RUN]` prefix
- Runs harmless read-only checks (pgrep, git status, ls, python3, etc.)
- Shows you exactly which paths will be accessed and cleaned

### Dry-Run 不会做什么 / What Dry-Run Does NOT Do

- **不会执行任何文件删除**（rm 只打印）
- **不会终止任何进程**（pkill 只打印）
- **不会修改 .zshrc**（awk 只打印）
- **不会实际 cp 任何文件**

- **Does NOT execute any file deletion**
- **Does NOT kill any process**
- **Does NOT modify .zshrc**
- **Does NOT actually copy any file**

### Dry-Run 的安全边界 / Dry-Run Safety Boundaries

Dry-run 仍然会做以下**只读操作**，这些不会影响你的文件：

Dry-run still performs the following **read-only** operations, which do not affect your files:

| 操作 | 说明 |
|------|------|
| `pgrep -x "claude"` | 只读进程查询 |
| `git status --short` | 只读 git 状态 |
| `ls -dt ...` | 只读目录列表 |
| `python3 -c "json.load(...)"` | 只读 JSON 解析 |
| `security dump-keychain` | 只读 keychain 查询（不会删除） |
| `read -p "..."` | 交互式询问（你可以随时 Ctrl-C） |

如果你连这些只读操作都不想让它执行，可以在阅读完脚本后，手动注释掉相关行。

If you want to avoid even these read-only operations, manually comment out the relevant lines after reading the script.

---

## 目录结构 / Directory Structure

```
.
├── scripts/
│   ├── claude-nuke-and-restore.sh      # 主脚本 / Main script (18 phases)
│   ├── backup-missing-to-safe-zone.sh  # 备份脚本 / Backup script
│   └── setup-proxy.sh                  # 代理安装 / Proxy installer
├── templates/
│   ├── settings.json                   # 通用配置模板 / Generic settings template
│   └── mcp.json                        # 空 MCP 模板 / Empty MCP template
├── docs/
│   ├── EXECUTE.md                      # 执行手册 / Execution manual
│   └── review-notes.md                 # 设计决策 / Design decisions
├── .ai/
│   └── agent-release-notes.md          # 发布记录 / Release notes
├── LICENSE                             # MIT
└── README.md                           # 本文档 / This document
```

---

## 系统要求 / System Requirements

- macOS
- bash 3.2+ (macOS 默认 / macOS default)
- python3
- npm (用于重新安装 Claude Code CLI / for reinstalling Claude Code CLI)

---

## 免责声明 / Disclaimer

本项目仅供学习和开发调试使用。使用本工具产生的任何后果由使用者自行承担。本项目不保证能够绕过任何平台的风控机制，也不鼓励违反任何服务条款的行为。

This project is for educational and development debugging purposes only. Users bear full responsibility for any consequences. This project does not guarantee bypassing any platform risk controls and does not encourage violating any terms of service.

---

## License

MIT
