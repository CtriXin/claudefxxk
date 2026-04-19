# claudefxxk

让 Claude 不认识这台电脑。

一个用于 **完全隔离 + 指纹重置** Claude Code CLI 的 macOS 脚本工具包。支持彻底清理身份痕迹、重新安装 CLI、并白名单恢复你的自定义资产（skills、hooks、plugins、CLAUDE.md 等）。

---

## 功能

- **完全隔离**: 删除 `~/.claude.json`、Keychain 凭证、Desktop App、浏览器数据、临时文件等所有身份痕迹
- **指纹重置**: 重新安装 Claude Code CLI 后生成全新 userID
- **资产白名单恢复**: 只恢复你备份的内容，不恢复任何可能携带旧指纹的数据
- **条件执行**: 所有扩展功能（MMS、cc-switch、.agents、MCP）都是 opt-in，未配置时 soft warning + final summary，绝不静默跳过
- **DRY-RUN 模式**: `DRY_RUN=1 ./scripts/claude-nuke-and-restore.sh` 只打印不执行

---

## 目录结构

```
.
├── scripts/
│   ├── claude-nuke-and-restore.sh      # 主脚本: 清理 + 重装 + 恢复 (18 阶段)
│   ├── backup-missing-to-safe-zone.sh  # 资产备份 + 脱敏
│   └── setup-proxy.sh                  # 安装 claude() proxy 函数到 ~/.zshrc
├── templates/
│   ├── settings.json                   # 通用 settings.json 模板
│   └── mcp.json                        # 空 MCP 模板
├── docs/
│   ├── EXECUTE.md                      # 执行手册
│   └── review-notes.md                 # 设计决策与 review 记录
├── LICENSE
└── README.md
```

---

## 快速开始

### 1. 配置

创建配置文件，告诉脚本你的项目路径：

```bash
mkdir -p ~/.config/claudefxxk
cat > ~/.config/claudefxxk/config.sh << 'EOF'
# 用于 git dirty 检查的目录（会在 phase 0 检查未提交修改）
SCAN_ROOTS=(
    "$HOME/project-a"
    "$HOME/project-b"
)

# 项目级 .claude 清理目录（phase 10）
# 默认空数组，不扫描任何目录；显式配置后才清理
CLEAN_ROOTS=(
    "$HOME/project-a"
    "$HOME/project-b"
)

# MCP server 项目目录（phase 17 扫描 mcp.json）
MCP_PROJECTS=(
    "$HOME/project-a"
)
EOF
```

### 2. 备份资产

```bash
./scripts/backup-missing-to-safe-zone.sh
```

输出到 `~/claude_safe_zone/backup-run-YYYYMMDD-HHMMSS/`。

### 3. 执行清理 + 重装 + 恢复

```bash
./scripts/claude-nuke-and-restore.sh
```

### 4. 安装代理（可选）

```bash
./scripts/setup-proxy.sh
```

安装一个 `claude()` 函数到 `~/.zshrc`，自动检测代理可用性并注入 IP/TZ 上下文。

---

## 配置说明

| 变量 | 用途 | 默认值 |
|------|------|--------|
| `SCAN_ROOTS` | git dirty 检查目录 | `()` |
| `CLEAN_ROOTS` | 项目级 `.claude` 清理目录 | `()` |
| `MCP_PROJECTS` | MCP server 项目目录 | `()` |

**重要**: `CLEAN_ROOTS` 默认为空，不会扫描 `$HOME`。如需清理项目级 `.claude` 数据，必须显式配置。

---

## 阶段说明

| 阶段 | 内容 | 可选 |
|------|------|------|
| 0 | 依赖检查 + 备份验证 + repo 检查 + 进程确认 | 否 |
| 1 | 终止 Claude 进程 | 否 |
| 2 | 核心身份文件 `~/.claude.json` / `~/.claude` | 否 |
| 3 | Keychain 凭证 | 否 |
| 4 | npm cache / global claude-code | 否 |
| 5 | `~/.config/Claude` | 否 |
| 6 | `~/Library/Logs/Claude` | 否 |
| 7 | `~/Library/Caches/com.anthropic.*` | 否 |
| 8 | Chrome 数据（可选关闭/跳过） | 是 |
| 9 | `/tmp` 临时文件 | 是 |
| 10 | 项目级 `.claude/` 追踪数据 | 是（需配置 CLEAN_ROOTS） |
| 11 | Desktop App 本体 | 是 |
| 12 | shell history | 是 |
| 13 | `.zshrc` proxy marker | 是 |
| 14 | git config email | 是 |
| 15 | 重新安装 Claude Code CLI | 是 |
| 16 | 首次启动验证 + userID 对比 | 否 |
| 17 | 恢复资产（白名单方式） | 否 |
| 18 | 最终验证 | 否 |

---

## 安全原则

1. **不在 MMS session 内运行**: 脚本会检测 `$HOME` 虚拟化，如果在 MMS 内运行会直接退出
2. **精确进程匹配**: 只杀 `Claude`/`claude`/`claude-code` 进程，不误杀其他含 "claude" 的进程
3. **不扫描整个 `$HOME`**: 项目级清理只针对 `CLEAN_ROOTS` 中配置的目录
4. **白名单恢复**: 只恢复备份目录中的已知文件，不恢复任何可能携带旧指纹的数据
5. **settings.json 自动脱敏**: 备份时自动剔除 `env` / `attribution` 等敏感字段

---

## 系统要求

- macOS
- bash 3.2+ (macOS 默认)
- python3
- npm (用于重新安装 Claude Code CLI)

---

## 许可证

MIT
