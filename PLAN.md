# claudefxxk 开源版最终可执行计划

> 确认原则（来自审查反馈）：
> 1. discussions 不直接复制，改 sanitized review notes
> 2. 零静默跳过，全部 soft warning + final summary
> 3. PROJECT_DIRS 彻底拆成 SCAN_ROOTS / CLEAN_ROOTS / MCP_PROJECTS
> 4. "不砍功能" → 核心清理完整保留，增强恢复为 optional（无配置时用内置模板兜底+warning）
> 5. 阶段编号和实际脚本对齐
> 6. setup-proxy.sh 明确 marker-based idempotent 安装

---

## 真实范围声明

**开源版完整保留的（零依赖，开箱即用）：**
- 18 阶段清理流程（身份、Keychain、Desktop、CLI、IDE、浏览器、history、.zshrc、git email、npm reinstall）
- DRY_RUN 零写入验证
- 首次启动验证 + userID 快照对比
- 基础白名单恢复（目录结构重建）

**增强恢复能力（依赖配置或内置模板兜底）：**
- Skills/Plugins/Hooks 恢复 → 依赖 `SAFE_ZONE` 中的备份（hooks 无内置兜底，settings 有内置模板）
- MCP 配置恢复 → 依赖 `MCP_PROJECTS` allowlist
- Settings 模板恢复 → 优先 `CODEX_BF`，fallback 内置 templates/
- Git dirty 检查 → 依赖 `SCAN_ROOTS`
- 代理自动配置 → 依赖 `setup-proxy.sh`

---

## 目录结构

```
claudefxxk-open-source/
├── README.md
├── LICENSE (MIT)
├── .gitignore
├── .claudefxxk.conf.example
├── docs/
│   ├── EXECUTE.md
│   ├── capability-matrix.md
│   ├── review-notes.md          # sanitized，不含私有路径/IP/内网信息
│   └── network-proxy.md
└── scripts/
    ├── claude-nuke-and-restore.sh
    ├── backup-missing-to-safe-zone.sh
    ├── setup-proxy.sh
    └── templates/
        ├── settings.json
        ├── statusline-command.sh
        └── mcp.json
```

**注意：没有 docs/discussions/。** 原始 agent 审查文档含私有信息，不直接开源。替换为 `docs/review-notes.md`，只保留方法论和审查结论，所有敏感信息 redacted。

---

## 1. 配置文件 .claudefxxk.conf.example

```bash
# ================================================================
# claudefxxk 配置文件
# 复制到 ~/.claudefxxk.conf，按需填写
# 未配置的项会在执行时 soft warning，最终 summary 列出
# ================================================================

# --- 备份与恢复根目录（必填，影响所有备份/恢复/兜底模板）---
# 不存在时：soft warning，尝试创建，创建失败则大部分恢复能力降级
SAFE_ZONE="$HOME/claude_safe_zone"

# --- Git 扫描根目录（可选，影响阶段 0 repo 检查和备份前 pre-check）---
# 只填具体项目父目录，不要填 $HOME
# 未配置时：soft warning "未配置 SCAN_ROOTS，跳过 git dirty 检查"
SCAN_ROOTS=(
    # "$HOME/projects"
)

# --- 清理扫描根目录（可选，影响 phase 10 项目级 .claude 清理）---
# 脚本会在这些目录下查找并删除残留的 .claude/ 子目录
# 未配置时：soft warning，默认不扫描（避免 find $HOME 的宽 blast radius）
# 用户必须显式填写才启用项目级 .claude 清理
CLEAN_ROOTS=()

# --- MCP 项目 allowlist（可选，影响 MCP 配置备份和恢复）---
# 必须显式列出项目根目录，不会自动扫描
# 未配置时：soft warning "未配置 MCP_PROJECTS，跳过 MCP 恢复"
MCP_PROJECTS=(
    # "$HOME/projects/my-agent"
)

# --- 私有 backfill 目录（可选，影响阶段 17 高级恢复）---
# 若配置且存在：优先从这里读取 settings/hooks/mcp 模板
# 若未配置或不存在：soft warning，fallback 到内置 scripts/templates/
CODEX_BF=""

# --- .zshrc 要清理的函数名（可选，有默认值）---
ZSHRC_FUNCTIONS_TO_REMOVE=("claude_safe" "claudep" "ccp")
```

---

## 2. scripts/claude-nuke-and-restore.sh

### 2.1 配置文件读取 + Warning 累积器

```bash
CONFIG_FILE="$HOME/.claudefxxk.conf"
SAFE_ZONE="$HOME/claude_safe_zone"
SCAN_ROOTS=()
CLEAN_ROOTS=()
MCP_PROJECTS=()
CODEX_BF=""
ZSHRC_FUNCTIONS_TO_REMOVE=("claude_safe" "claudep" "ccp")
WARNINGS=""

[ -f "$CONFIG_FILE" ] && source "$CONFIG_FILE"

# SAFE_ZONE 检查（影响所有恢复）
if [ ! -d "$SAFE_ZONE" ]; then
    mkdir -p "$SAFE_ZONE" 2>/dev/null || true
    if [ ! -d "$SAFE_ZONE" ]; then
        echo "[WARN] SAFE_ZONE '$SAFE_ZONE' 不可写，备份和恢复能力将严重受限"
        WARNINGS="$WARNINGS SAFE_ZONE_UNWRITABLE"
    fi
fi
```

### 2.2 阶段通用化（和实际脚本对齐）

| 实际阶段 | 内容 | 开源版修改 |
|---------|------|-----------|
| 0 | 前置确认 | 依赖检查、备份验证、API key 提示 |
| 0.3 | repo 检查 | 遍历 `SCAN_ROOTS`。为空 → `[WARN] SCAN_ROOTS 未配置，跳过 git 检查` |
| 0.4 | 进程检查 | MMS：若 `~/.config/mms/` 存在则展示，不存在 → `[WARN] MMS 未安装，跳过 MMS 相关清理` |
| 1 | 杀进程 | 若 MMS 未安装，统一按 "Claude 进程" 处理，不分类 |
| 2 | 核心身份 | 保留 |
| 3 | Keychain | 保留 |
| 4 | Desktop App | 保留 |
| 5 | CLI 安装物 | 保留 |
| 6 | IDE 扩展 | 保留 |
| 7 | MMS/MMC | 若 `~/.config/mms/` 存在则执行，不存在 → soft warning，跳过 |
| 8 | 浏览器数据 | 保留 |
| 9 | /tmp | 保留 |
| 10 | 项目级 .claude/（明确路径） | 遍历 `CLEAN_ROOTS`。为空 → `[WARN] CLEAN_ROOTS 未配置，仅扫描已知路径` |
| 11 | Desktop App 本体 + URL Handler | 保留 |
| 12 | shell history | 保留 |
| 13 | .zshrc 中的 claude 函数 | 使用 `ZSHRC_FUNCTIONS_TO_REMOVE`，数组为空 → soft warning |
| 14 | git config email | 保留 |
| 15 | 重新安装 CLI | 保留 |
| 16 | 首次启动验证 | 保留 |
| 17 | 恢复资产 | 见 2.3 |
| 18 | 最终验证 | 保留 |
| Final | Summary | 新增：打印 WARNINGS 累积结果 |

### 2.3 阶段 17 恢复资产（优先级链）

```
CLAUDE.md:
  1. $SAFE_ZONE/CLAUDE.md
  2. 内置 templates/CLAUDE.md（空模板兜底）
  不存在 → [WARN] "CLAUDE.md 未找到，恢复为空"

settings.json:
  1. $SAFE_ZONE/settings-current-session-sanitized.json
  2. $CODEX_BF/templates/settings.json（若 CODEX_BF 配置且存在）
  3. 内置 scripts/templates/settings.json
  全部不存在 → [WARN] "settings.json 未找到，使用空配置"

Hooks（~/.claude/hooks/）：
  1. $SAFE_ZONE/hooks/
  2. $CODEX_BF/templates/hooks/（若存在）
  全部不存在 → [WARN] "Hooks 备份缺失，恢复为空"
  注意：statusline-command.sh 是 settings.json 的 statusLine.command 字段，
        不是 hooks。内置 templates/settings.json 已包含基础 statusLine 配置。

MCP:
  1. 遍历 MCP_PROJECTS，逐个恢复 .mcp.json
  2. $CODEX_BF/templates/mcp.json（若存在）
  3. 内置 scripts/templates/mcp.json
  MCP_PROJECTS 为空 → [WARN] "MCP_PROJECTS 未配置，跳过 MCP 恢复"
```

### 2.4 Final Summary（新增，阶段 17 之后）

```bash
echo ""
echo "========================================"
echo "执行 Summary"
echo "========================================"

if [ -n "$WARNINGS" ]; then
    echo "[WARN] 以下能力因缺少配置或资产而未完全启用："
    for w in $WARNINGS; do
        case "$w" in
            SAFE_ZONE_UNWRITABLE) echo "  - SAFE_ZONE 不可写：备份/恢复能力受限" ;;
            SCAN_ROOTS_EMPTY)     echo "  - SCAN_ROOTS 未配置：跳过 git dirty 检查" ;;
            CLEAN_ROOTS_FALLBACK) echo "  - CLEAN_ROOTS 未配置：跳过项目级 .claude 清理" ;;
            MCP_PROJECTS_EMPTY)   echo "  - MCP_PROJECTS 未配置：跳过 MCP 恢复" ;;
            CODEX_BF_MISSING)     echo "  - CODEX_BF 未配置：使用内置模板兜底" ;;
            MMS_NOT_INSTALLED)    echo "  - MMS 未安装：跳过 MMS 清理" ;;
            CC_SWITCH_NOT_FOUND)  echo "  - cc-switch 未安装：跳过清理" ;;
            HOOKS_FALLBACK)       echo "  - Hooks 备份缺失：使用内置模板" ;;
            SETTINGS_FALLBACK)    echo "  - Settings 备份缺失：使用内置模板" ;;
        esac
    done
    echo ""
    echo "若要完整恢复，请配置 ~/.claudefxxk.conf 并准备 SAFE_ZONE 备份"
else
    echo "[OK] 所有配置项已就绪，无 warning"
fi

echo ""
echo "已恢复内容："
# 逐行列出实际恢复的文件和来源
```

---

## 3. scripts/backup-missing-to-safe-zone.sh

| 功能 | 修改 |
|------|------|
| SAFE_ZONE | 读取配置，不存在则尝试创建，创建失败 → error exit |
| Git pre-check | 遍历 `SCAN_ROOTS`，为空 → soft warning |
| MMS settings | 若 `~/.config/mms/` 存在则备份，不存在 → soft warning |
| repo-mcp | 遍历 `MCP_PROJECTS` allowlist，为空 → soft warning |
| 内置模板 | 若 `CODEX_BF` 不存在，不报错 |
| Final Summary | 列出备份了哪些、哪些因缺少配置跳过 |

---

## 4. scripts/setup-proxy.sh（idempotent）

### 机制

```bash
MARKER_BEGIN="# >>> claudefxxk proxy"
MARKER_END="# <<< claudefxxk proxy"
PROXY_FILE="$HOME/.config/claudefxxk/claude-proxy.zsh"

install() {
    mkdir -p "$HOME/.config/claudefxxk"
    generate_proxy > "$PROXY_FILE"
    
    if grep -q "$MARKER_BEGIN" "$HOME/.zshrc"; then
        # 已存在：替换 marker 间内容
        awk -v begin="$MARKER_BEGIN" -v end="$MARKER_END" -v source="source $PROXY_FILE" '
            $0 ~ begin { print; print source; skip=1; next }
            $0 ~ end { skip=0; print; next }
            !skip { print }
        ' "$HOME/.zshrc" > "$HOME/.zshrc.tmp" && mv "$HOME/.zshrc.tmp" "$HOME/.zshrc"
        echo "[OK] 已更新 ~/.zshrc"
    else
        # 不存在：追加
        echo "" >> "$HOME/.zshrc"
        echo "$MARKER_BEGIN" >> "$HOME/.zshrc"
        echo "source $PROXY_FILE" >> "$HOME/.zshrc"
        echo "$MARKER_END" >> "$HOME/.zshrc"
        echo "[OK] 已追加到 ~/.zshrc"
    fi
}

uninstall() {
    awk -v begin="$MARKER_BEGIN" -v end="$MARKER_END" '
        $0 ~ begin { skip=1; next }
        $0 ~ end { skip=0; next }
        !skip { print }
    ' "$HOME/.zshrc" > "$HOME/.zshrc.tmp" && mv "$HOME/.zshrc.tmp" "$HOME/.zshrc"
    rm -f "$PROXY_FILE"
    echo "[OK] 已卸载"
}
```

### 交互流程

```
1. 欢迎
2. 主代理地址 [默认: http://127.0.0.1:7897]
3. Fallback 代理地址 [默认: 空]
4. TZ 兜底 [默认: America/Los_Angeles]
5. 测试主代理连通性（curl 查 IP）
6. 测试时区检测（ip-api.com）
7. 生成 $PROXY_FILE
8. 写入 ~/.zshrc（idempotent，重复执行不追加）
9. 提示 source ~/.zshrc
```

---

## 5. 内置 Templates（scripts/templates/）

当用户未配置 CODEX_BF 或备份缺失时，用这些兜底：

- `settings.json` — 最小可用：empty permissions, basic bypass, empty mcpServers
- `statusline-command.sh` — settings.json 的 statusLine.command 字段模板（不是 hooks）
- `mcp.json` — 最小可用：空 servers 数组

---

## 6. 文档

### docs/review-notes.md（替代 discussions/）

不含任何私有信息。只保留：
- 审查方法论（多 agent 交叉审查）
- 发现的 bug 类别总结（set -e 陷阱、命令替换、管道返回值）
- 修复策略总结
- 不保留：任何具体路径、IP、repo 名、内网信息

### docs/capability-matrix.md

| 功能 | 配置项 | 未配置行为 | 内置兜底 |
|------|--------|-----------|---------|
| Git dirty 检查 | SCAN_ROOTS | soft warning，跳过 | 无 |
| 项目级 .claude 清理 | CLEAN_ROOTS | soft warning，跳过清理 | 无 |
| MCP 恢复 | MCP_PROJECTS | soft warning，跳过 | scripts/templates/mcp.json |
| Settings 恢复 | SAFE_ZONE / CODEX_BF | soft warning，用内置模板 | scripts/templates/settings.json |
| Hooks 恢复 | SAFE_ZONE / CODEX_BF | soft warning，恢复为空 | 无（hooks 需用户自行备份） |
| Settings statusLine | SAFE_ZONE / CODEX_BF | soft warning，用内置模板 | scripts/templates/settings.json（含基础 statusLine） |
| MMS 清理 | 自动检测 ~/.config/mms/ | soft warning，跳过 | 无 |
| cc-switch 清理 | 自动检测 ~/.cc-switch/ | soft warning，跳过 | 无 |
| 代理配置 | setup-proxy.sh 交互 | 无代理 | 无 |

### 其他
- `README.md` — 通用入口，macOS-only 标注，与个人版区别说明
- `docs/EXECUTE.md` — 执行手册，含配置和代理安装章节
- `docs/network-proxy.md` — 通用化代理说明

---

## 7. 私有硬编码全面清理（最终清单）

| 文件 | 当前硬编码 | 开源版 |
|------|-----------|--------|
| `claude-nuke-and-restore.sh:50` | `claude_safe_zone` | `SAFE_ZONE` 变量，默认 `~/claude_safe_zone` |
| `claude-nuke-and-restore.sh:168` | `agent-im` 路径 | `SCAN_ROOTS` 扫描 |
| `claude-nuke-and-restore.sh:177-179` | `multi-model-switch` 等 | `SCAN_ROOTS` 扫描 |
| `claude-nuke-and-restore.sh:346` | `backups/backup-$TIMESTAMP` | `SAFE_ZONE` 变量 |
| `claude-nuke-and-restore.sh:350-354` | `cc-switch` | 自动检测存在性 |
| `claude-nuke-and-restore.sh:823` | `statusline-command.sh` 绝对路径 | 内置 templates/ |
| `backup-missing-to-safe-zone.sh:26` | `claude_safe_zone` | `SAFE_ZONE` 变量 |
| `backup-missing-to-safe-zone.sh:43-58` | `agent-im` pre-check | `SCAN_ROOTS` 扫描 |
| `backup-missing-to-safe-zone.sh:105` | `internal-comms` | 从配置读取 |
| `backup-missing-to-safe-zone.sh:195` | MMS settings.json | 自动检测存在性 |
| `backup-missing-to-safe-zone.sh:229-231` | repo-mcp 私有列表 | `MCP_PROJECTS` allowlist |

---

## 8. GitHub 推送

```bash
cd ~/auto-skills/CtriXin-repo/claudefxxk-open-source
git branch -m main
git remote add origin git@github.com:CtriXin/claudefxxk.git
git add .
git commit -m "init: open-source version

- 18-stage isolation script with configurable paths
- backup script with soft warning + final summary
- setup-proxy.sh with marker-based idempotent install
- built-in OSS templates for settings/hooks/mcp
- capability matrix documenting all optional features"
git push -u origin main
```

---

## 最终确认

- [ ] **GitHub 仓库 `CtriXin/claudefxxk` 已创建？**
- [ ] **MIT LICENSE OK？**
- [ ] **内置 templates 范围**：settings.json（含基础 statusLine）+ mcp.json，足够？
  （hooks 无内置兜底，需用户自行备份到 SAFE_ZONE）
- [ ] **marker 格式**：`# >>> claudefxxk proxy` / `# <<< claudefxxk proxy`，OK？
- [ ] **discussions 处理**：不复制原始文档，替换为 sanitized review-notes.md，OK？

确认后执行，本地仓库不动。
