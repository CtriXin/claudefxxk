# claudefxxk — Claude 指纹重置工具

让 Claude Code CLI 不认识这台电脑。

**[English Version →](README.en.md)**

---

## 这是什么

`claudefxxk` 是一组 macOS 上的 bash 脚本，用于：

1. **完全隔离** — 彻底清理 Claude Code CLI 的身份痕迹
2. **指纹重置** — 重新安装 CLI 后生成全新 userID
3. **白名单恢复** — 只恢复你备份的自定义资产（skills、hooks、plugins、CLAUDE.md 等）

**核心设计原则：**
- 显式配置，绝不静默扫描 `$HOME`
- 条件执行，工具不存在时 soft warning，不静默跳过
- Dry-Run 先行，destructive 操作只打印不执行
- 白名单恢复，不恢复任何可能携带旧指纹的数据

---

## 它会做什么

| 能力 |
|------|
| 终止所有 Claude / claude / claude-code 进程 |
| 删除 `~/.claude.json`（Claude 身份文件） |
| 删除 Keychain 中的 Claude 凭证 |
| 清理 npm cache 中的 claude-code |
| 删除 `~/.config/Claude` 和 Desktop App |
| 清理浏览器中的 Claude 相关数据（可选） |
| 清理 shell history 中的 claude 记录（可选） |
| 重新安装 Claude Code CLI（可选） |
| 白名单恢复你的 skills / hooks / plugins / CLAUDE.md |
| 对比新旧 userID，确认身份已重置 |

---

## 它不会做什么

| 不会做的事 | 说明 |
|------------|------|
| **不会删除你的代码文件** | 只清理 Claude 相关痕迹，不动你的项目代码 |
| **不会删除 git repository** | 不碰任何 `.git/` 目录 |
| **不会修改系统级配置** | 只修改可选的 git email 和 `.zshrc` proxy marker |
| **不会扫描整个 `$HOME`** | 只清理你显式配置的 `CLEAN_ROOTS` |
| **不会删除 MMS 主进程或配置** | 只终止 MMS 下的 Claude 子进程，保留 MMS |
| **不保证绕过任何平台风控** | 这是一个开发/调试工具，不是绕过服务条款的产品 |
| **不会自动帮你登录 Claude** | 重装后需要手动 OAuth 登录 |

---

## 不建议做的事情

1. **不要在 MMS / Claude CLI session 内运行主脚本**
   - 脚本会检测 `$HOME` 虚拟化，如果在 MMS 内运行会直接退出
   - 请在系统原生 Terminal / iTerm2 中运行

2. **不要跳过 Dry-Run**
   - 首次使用前务必先 `DRY_RUN=1` 跑一次，确认它要做什么

3. **不要在没有备份的情况下运行**
   - 先运行 `backup-missing-to-safe-zone.sh`，确认资产已备份

4. **不要期望这是"一键解封"**
   - 这是一个开发/调试工具，不是绕过平台规则的产品

---

## 建议自己修改或让 LLM 再检查的部分

以下配置强烈建议你在使用前仔细检查，必要时让 LLM 帮你 review：

### 1. `~/.config/claudefxxk/config.sh` — 路径配置

```bash
CLEAN_ROOTS=(
    "$HOME/your-project-a"
    "$HOME/your-project-b"
)
```

**务必确认**：这些目录确实包含你想要清理的 `.claude/` 痕迹，且没有放错路径。`CLEAN_ROOTS` 默认为空，不配置就不会清理任何项目级 `.claude` 数据。

### 2. `templates/settings.json` — statusLine 路径

```json
"statusLine": {
  "type": "command",
  "command": "/bin/bash -c 'echo \"[Claude] $(date +%H:%M:%S) | $(whoami)@$(hostname -s)\"'"
}
```

这是一个通用 fallback。如果你有自己的 `statusline-command.sh`，请在恢复后手动替换这个路径。

### 3. MCP server 配置

`MCP_PROJECTS` 中的项目会被扫描 `mcp.json`。请确认这些项目的 `mcp.json` 不包含敏感凭证（如 API key、token）。

### 4. 权限配置（permissions.allow / deny）

默认配置允许较广泛的 bash 命令。如果你所在环境有特殊安全要求，请让 LLM 帮你审查 `templates/settings.json` 中的 `permissions` 字段。

---

## Dry-Run 模式详解

### 怎么跑

```bash
DRY_RUN=1 ./scripts/claude-nuke-and-restore.sh
```

### Dry-Run 会做什么

- 打印所有 `rm`、`pkill`、`cp` 等 destructive 命令（前缀 `[DRY-RUN]`）
- 运行无害的只读检查（`pgrep`、`git status`、`ls`、`python3 -c` 等）
- 让你看到脚本会访问哪些路径、清理哪些文件

### Dry-Run 不会做什么

- **不会执行任何文件删除**（rm 只打印）
- **不会终止任何进程**（pkill 只打印）
- **不会修改 .zshrc**（awk 只打印）
- **不会实际 cp 任何文件**

### Dry-Run 的安全边界

Dry-run 仍然会做以下**只读操作**，这些不会影响你的文件：

| 操作 | 说明 |
|------|------|
| `pgrep -x "claude"` | 只读进程查询 |
| `git status --short` | 只读 git 状态 |
| `ls -dt ...` | 只读目录列表 |
| `python3 -c "json.load(...)"` | 只读 JSON 解析 |
| `security dump-keychain` | 只读 keychain 查询（不会删除） |
| `read -p "..."` | 交互式询问（你可以随时 Ctrl-C） |

如果你连这些只读操作都不想让它执行，可以在阅读完脚本后，手动注释掉相关行。

---

## 执行步骤

### Step 0: 克隆

```bash
git clone git@github.com:CtriXin/claudefxxk.git
cd claudefxxk
```

### Step 1: 配置

```bash
mkdir -p ~/.config/claudefxxk
cat > ~/.config/claudefxxk/config.sh << 'EOF'
# 用于 git dirty 检查
SCAN_ROOTS=(
    "$HOME/your-project-a"
    "$HOME/your-project-b"
)

# 用于项目级 .claude 清理（默认空数组，不扫描任何目录）
CLEAN_ROOTS=(
    "$HOME/your-project-a"
    "$HOME/your-project-b"
)

# MCP server 项目目录
MCP_PROJECTS=(
    "$HOME/your-project-a"
)
EOF
```

### Step 2: 备份资产

```bash
./scripts/backup-missing-to-safe-zone.sh
```

输出到 `~/claude_safe_zone/backup-run-YYYYMMDD-HHMMSS/`。确认包含 hooks/、skills-entity/、CLAUDE.md 等。

### Step 3: Dry-Run 测试

```bash
DRY_RUN=1 ./scripts/claude-nuke-and-restore.sh
```

这会打印所有 18 个阶段将要执行的命令，但**不会实际删除任何文件**。

### Step 4: 正式执行

```bash
./scripts/claude-nuke-and-restore.sh
```

按提示逐步确认。关键决策点：
- Phase 0: API key 已处理？repo 已 push？
- Phase 1: MMS 工作已保存？（如果 MMS 正在运行）
- Phase 8: Chrome 处理（s=跳过, k=自动关闭, 回车=确认）
- Phase 15: 是否 npm 重新安装
- Phase 16: 自动对比新旧 userID

### Step 5: 安装代理（可选）

```bash
./scripts/setup-proxy.sh
source ~/.zshrc
```

---

## 目录结构

```
.
├── scripts/
│   ├── claude-nuke-and-restore.sh      # 主脚本（18 阶段）
│   ├── backup-missing-to-safe-zone.sh  # 资产备份 + 脱敏
│   └── setup-proxy.sh                  # 代理安装
├── templates/
│   ├── settings.json                   # 通用配置模板
│   └── mcp.json                        # 空 MCP 模板
├── docs/
│   ├── EXECUTE.md                      # 执行手册
│   └── review-notes.md                 # 设计决策
├── .ai/
│   └── agent-release-notes.md          # 发布记录
├── LICENSE                             # MIT
└── README.md                           # 本文档（中文版）
```

---

## 系统要求

- macOS
- bash 3.2+（macOS 默认）
- python3
- npm（用于重新安装 Claude Code CLI）

---

## 免责声明

本项目仅供学习和开发调试使用。使用本工具产生的任何后果由使用者自行承担。本项目不保证能够绕过任何平台的风控机制，也不鼓励违反任何服务条款的行为。

---

## License

MIT

---

**[English Version →](README.en.md)**
