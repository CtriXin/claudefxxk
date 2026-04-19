# claudefxxk 开源版计划 v2（通用化，不砍掉）

## 核心策略
- **本地 `claudefxxk/` 不动**，所有改动在 `claudefxxk-open-source/`
- **不砍掉任何功能**，只把硬编码路径改成可配置/自动检测
- 用户没安装的工具 → 脚本检测到不存在就静默跳过，不提示

---

## 通用化修改清单

### 1. MMS（保留，自动检测）
- `~/.config/mms/` 存在 → 正常处理（进程保护、网关清理）
- `~/.config/mms/` 不存在 → 阶段 0 不显示 MMS 信息，阶段 7 跳过

### 2. cc-switch（保留，自动检测）
- `~/.cc-switch` 存在 → 清理 db/logs
- `~/.cc-switch` 不存在 → 静默跳过

### 3. Codex backfill（保留，自动检测）
- `CODEX_BF` 目录存在 → 阶段 17 从模板恢复
- `CODEX_BF` 不存在 → 跳过 fallback

### 4. agent-im git 检查（保留，路径可配置）
- 从 `AGENT_IM_DIR="~/auto-skills/CtriXin-repo/agent-im"` 硬编码
- 改为：读取 `~/.claudefxxk.conf` 中的 `PROJECT_DIRS` 数组，扫描每个目录下的 git repo
- 无配置 → 跳过 git 检查（不报错）

### 5. repo-mcp（保留，路径可配置）
- 从硬编码 `mindkeeper/.mcp.json` 等
- 改为：扫描 `PROJECT_DIRS` 中每个项目下的 `.mcp.json`，自动备份

### 6. KNOWN_PROJECTS（保留，路径可配置）
- 从硬编码列表
- 改为：读取 `~/.claudefxxk.conf` 中的 `PROJECT_DIRS`

### 7. ~/.zshrc claude() 函数（保留逻辑，不自动注入）
- 脚本不再自动修改 `~/.zshrc`
- 改为：把 `claude-proxy.zsh` 放在 `scripts/`，用户手动 `cat >> ~/.zshrc`
- 提供一键命令文档

---

## 新增配置文件

`~/.claudefxxk.conf`（可选，不存在则所有功能静默跳过）：

```bash
# 项目目录（git dirty 检查、mcp 恢复用）
PROJECT_DIRS=(
    "$HOME/projects/my-agent"
)

# Codex backfill 模板目录（可选）
CODEX_BF="$HOME/claude_safe_zone/codex-backfill"

# 代理配置（claude-proxy.zsh 用）
CLD_PROXY_PRIMARY="http://127.0.0.1:7897"
CLD_PROXY_FALLBACK=""
```

---

## 目录结构

```
claudefxxk-open-source/
├── README.md
├── LICENSE
├── .gitignore
├── .claudefxxk.conf.example
├── docs/
│   ├── EXECUTE.md
│   ├── what-you-lose.md（改为 what-is-configurable.md）
│   ├── network-proxy.md
│   └── discussions/
└── scripts/
    ├── claude-nuke-and-restore.sh
    ├── backup-missing-to-safe-zone.sh
    └── claude-proxy.zsh
```

---

## 文档调整

- `what-you-lose.md` → 改为 `what-is-configurable.md`
- 内容从"砍掉的功能"改为"需要配置才能启用的功能"
- 每个可配置项给示例

---

确认后执行。
