#!/bin/bash
# ============================================================================
# Safe Zone 资产补充脚本 v3（最终版）
# 更新:
#   - 输出到带时间戳的子目录，不污染 safe_zone 顶层
#   - 备份 session settings.json 时自动剔除敏感字段（token/env/attribution）
#   - 修正实体 skill 判断（经实机验证，排除 symlink）
#   - 兼容 Codex backfill，检测到时不重复
# ============================================================================

set -e

# ============================================================================
# 开源版配置读取
# ============================================================================
CONFIG_FILE="${CLAUDEFXXK_CONFIG:-$HOME/.config/claudefxxk/config.sh}"
if [ -f "$CONFIG_FILE" ]; then
    echo "ℹ️  读取配置文件: $CONFIG_FILE"
    # shellcheck source=/dev/null
    source "$CONFIG_FILE"
fi

# 默认值
[ -z "${SCAN_ROOTS+x}" ]   && declare -a SCAN_ROOTS=()
[ -z "${CLEAN_ROOTS+x}" ]  && declare -a CLEAN_ROOTS=()
[ -z "${MCP_PROJECTS+x}" ] && declare -a MCP_PROJECTS=()

# Warning 累积器
WARNINGS=()
warn() {
    local msg="$1"
    WARNINGS+=("$msg")
    echo "⚠️  $msg"
}

# P0: $HOME 虚拟化检测
REAL_HOME=$(eval echo "~$(whoami)")
if [ "$HOME" != "$REAL_HOME" ]; then
    echo "❌ 错误: \$HOME 被虚拟化"
    echo "   当前 \$HOME: $HOME"
    echo "   真实 home:   $REAL_HOME"
    echo "   此脚本必须在真实终端运行，不能在 Claude/MMS session 内执行。"
    exit 1
fi

# P3: python3 前置检查
command -v python3 >/dev/null 2>&1 || { echo "❌ 缺少 python3"; exit 1; }

: ${SAFE_ZONE:="$HOME/claude_safe_zone"}
: ${CODEX_BF:="$HOME/claude_safe_zone/codex-safe-zone-backfill-20260418"}
if [ -n "$CODEX_BF" ] && [ ! -d "$CODEX_BF" ]; then
    CODEX_BF=""
fi
SOURCE_BAK="$HOME/.claude.bak"
TIMESTAMP=$(date +%Y%m%d-%H%M%S)
OUTPUT_DIR="$SAFE_ZONE/backup-run-$TIMESTAMP"

mkdir -p "$OUTPUT_DIR"

echo "========================================"
echo "Safe Zone 资产补充脚本 v3（最终版）"
echo "========================================"
echo "输出目录: $OUTPUT_DIR"
echo ""

# ----------------------------------------------------------------------------
# 前置检查
# ----------------------------------------------------------------------------
echo "[PRE-CHECK] repo git 状态..."
if [ ${#SCAN_ROOTS[@]} -eq 0 ]; then
    warn "SCAN_ROOTS 未配置，跳过 git dirty 检查"
    echo "   如需检查，在 ~/.config/claudefxxk/config.sh 中设置:"
    echo "     SCAN_ROOTS=(\"\$HOME/project-a\" \"\$HOME/project-b\")"
fi
DIRTY_COUNT=0
for repo in "${SCAN_ROOTS[@]}"; do
    [ -d "$repo/.git" ] || continue
    dcount=$(cd "$repo" && git status --short 2>/dev/null | wc -l | tr -d ' ')
    if [ "$dcount" -gt 0 ]; then
        warn "$repo 有 $dcount 个未提交修改"
        DIRTY_COUNT=$((DIRTY_COUNT + dcount))
    fi
done
if [ "$DIRTY_COUNT" -gt 0 ]; then
    echo "  共检测到 $DIRTY_COUNT 个未提交修改。"
    echo "  继续备份不会修改这些 repo，但建议先 commit/push。"
    echo "  选择: y=继续备份  N/Enter=退出"
    read -p "  是否继续备份? [y/N]: " CONTINUE
    if [ "$CONTINUE" != "y" ] && [ "$CONTINUE" != "Y" ]; then
        exit 1
    fi
else
    echo "  ✓ 所有 repo git 干净"
fi

CODEX_EXISTS=false
[ -d "$CODEX_BF" ] && CODEX_EXISTS=true

echo ""

# ----------------------------------------------------------------------------
# P0: 全局 CLAUDE.md
# ----------------------------------------------------------------------------
echo "[P0] 全局 CLAUDE.md..."
if [ "$CODEX_EXISTS" = true ] && [ -f "$CODEX_BF/templates/CLAUDE.global.md" ]; then
    cp "$CODEX_BF/templates/CLAUDE.global.md" "$OUTPUT_DIR/CLAUDE.md"
    echo "  ✓ 从 Codex backfill 复制"
elif [ -f "$SOURCE_BAK/CLAUDE.md" ]; then
    cp "$SOURCE_BAK/CLAUDE.md" "$OUTPUT_DIR/CLAUDE.md"
    echo "  ✓ 从 .claude.bak 复制"
else
    echo "  ⚠ 找不到"
fi

# ----------------------------------------------------------------------------
# P0: settings.local.json
# ----------------------------------------------------------------------------
echo "[P0] settings.local.json..."
if [ -f "$SOURCE_BAK/.claude/settings.local.json" ]; then
    cp "$SOURCE_BAK/.claude/settings.local.json" "$OUTPUT_DIR/settings.local.json"
    echo "  ✓ 已复制"
else
    echo "  ⚠ 找不到"
fi

# ----------------------------------------------------------------------------
# P0: 真正的实体 Skills（经实机验证，排除 symlink）
# ----------------------------------------------------------------------------
echo "[P0] 真正的实体 skills（经实机验证）..."
mkdir -p "$OUTPUT_DIR/skills-entity"

SKILLS_ENTITY=(
    "changelog-generator"
    "doc-coauthoring"
    "domain-service-lookup"
    "domain-tool-expert"
    "find-skills"
    "image-enhancer"
    "internal-comms"
    "knowledge-wiki"
    "pptx"
)

BACKED=0
if [ -d "$SOURCE_BAK/skills" ]; then
    cd "$SOURCE_BAK/skills"
    for skill in "${SKILLS_ENTITY[@]}"; do
        if [ -d "$skill" ] && [ ! -L "$skill" ]; then
            # 检查 Codex backfill 是否已有
            if [ "$CODEX_EXISTS" = true ] && [ -d "$CODEX_BF/entity-skills-from-claude-bak/$skill" ]; then
                echo "  ⊘ $skill (Codex backfill 已存在)"
                continue
            fi
            cp -r "$skill" "$OUTPUT_DIR/skills-entity/"
            echo "  ✓ $skill (实体目录)"
            BACKED=$((BACKED + 1))
        fi
    done
fi
echo "  小结: 新备份 $BACKED 个实体 skill"

# 记录 .claude.bak/skills 中所有 symlink 的映射（供后续重建用）
if [ -d "$SOURCE_BAK/skills" ]; then
    cd "$SOURCE_BAK/skills"
    SYMLINK_MAP="$OUTPUT_DIR/skills.symlink-map.txt"
    echo "# .claude.bak/skills symlink 映射 — $TIMESTAMP" > "$SYMLINK_MAP"
    for d in *; do
        if [ -L "$d" ]; then
            echo "$d -> $(readlink "$d")" >> "$SYMLINK_MAP"
        fi
    done
    echo "  ✓ symlink 映射已写入 $SYMLINK_MAP"
fi

# ----------------------------------------------------------------------------
# P0: .cc-switch/skills/ 和 .agents/skills/
# ----------------------------------------------------------------------------
echo "[P0] .cc-switch/skills/..."
if [ "$CODEX_EXISTS" = true ] && [ -d "$CODEX_BF/cc-switch-skills" ]; then
    echo "  ⊘ Codex backfill 已包含"
elif [ -d "$HOME/.cc-switch/skills" ]; then
    cp -r "$HOME/.cc-switch/skills" "$OUTPUT_DIR/cc-switch-skills"
    echo "  ✓ 已复制"
else
    echo "  ⚠ 找不到"
fi

echo "[P0] .agents/skills/..."
if [ "$CODEX_EXISTS" = true ] && [ -d "$CODEX_BF/agents-skills" ]; then
    echo "  ⊘ Codex backfill 已包含"
elif [ -d "$HOME/.agents/skills" ]; then
    cp -r "$HOME/.agents/skills" "$OUTPUT_DIR/agents-skills"
    echo "  ✓ 已复制"
else
    echo "  ⚠ 找不到"
fi

# ----------------------------------------------------------------------------
# P1: Plugins
# ----------------------------------------------------------------------------
echo "[P1] plugins..."
PLUGIN_SOURCE=""
if [ -d "$HOME/.claude/plugins" ]; then PLUGIN_SOURCE="$HOME/.claude/plugins"
elif [ -d "$SOURCE_BAK/plugins" ]; then PLUGIN_SOURCE="$SOURCE_BAK/plugins"; fi
if [ -n "$PLUGIN_SOURCE" ]; then
    cp -r "$PLUGIN_SOURCE" "$OUTPUT_DIR/plugins"
    echo "  ✓ 已复制 (来源: $PLUGIN_SOURCE)"
else
    echo "  ⚠ 找不到"
fi

# ----------------------------------------------------------------------------
# P1: RTK.md
# ----------------------------------------------------------------------------
echo "[P1] RTK.md..."
if [ -f "$SOURCE_BAK/RTK.md" ]; then
    cp "$SOURCE_BAK/RTK.md" "$OUTPUT_DIR/RTK.md"
    echo "  ✓ 已复制"
else
    echo "  ⚠ 找不到"
fi

# ----------------------------------------------------------------------------
# P1: 当前 session 的 settings.json（自动剔除敏感字段）
# ----------------------------------------------------------------------------
echo "[P1] 当前 session settings.json（自动脱敏）..."
CURRENT_SETTINGS=""
# 优先从 MMS gateway 取最新 settings.json（如果存在）
if [ -d "$HOME/.config/mms/claude-gateway" ]; then
    LATEST_SETTINGS=$(ls -t "$HOME/.config/mms/claude-gateway/s"/*/.claude/settings.json 2>/dev/null | head -1)
    [ -n "$LATEST_SETTINGS" ] && [ -f "$LATEST_SETTINGS" ] && CURRENT_SETTINGS="$LATEST_SETTINGS"
fi
# fallback 到 ~/.claude/settings.json
[ -z "$CURRENT_SETTINGS" ] && [ -f "$HOME/.claude/settings.json" ] && CURRENT_SETTINGS="$HOME/.claude/settings.json"

if [ -n "$CURRENT_SETTINGS" ]; then
    python3 << PYEOF
import json, os, sys
src = "$CURRENT_SETTINGS"
dst = "$OUTPUT_DIR/settings-current-session-sanitized.json"
try:
    with open(src) as f:
        d = json.load(f)
    # 剔除所有敏感字段
    d.pop("env", None)
    d.pop("attribution", None)
    # 如果 env 中有非敏感的，可以保留白名单（目前全部剔除更安全）
    with open(dst, "w") as f:
        json.dump(d, f, indent=2)
    print(f"  ✓ 已脱敏备份: {dst}")
    print(f"    (来源: {src}, 已剔除 env + attribution)")
except Exception as e:
    print(f"  ⚠ 解析失败: {e}")
PYEOF
else
    echo "  ⚠ 当前 session settings.json 未找到"
fi

# ----------------------------------------------------------------------------
# P1: repo 级 .mcp.json
# ----------------------------------------------------------------------------
echo "[P1] repo 级 .mcp.json..."
mkdir -p "$OUTPUT_DIR/repo-mcp"
MCP_COUNT=0
for proj in "${MCP_PROJECTS[@]}"; do
    [ -d "$proj" ] || { warn "MCP_PROJECTS 路径不存在: $proj"; continue; }
    mcpfile="$proj/mcp.json"
    if [ -f "$mcpfile" ]; then
        basename=$(basename "$proj")
        cp "$mcpfile" "$OUTPUT_DIR/repo-mcp/${basename}.mcp.json"
        echo "  ✓ ${basename}.mcp.json"
        MCP_COUNT=$((MCP_COUNT + 1))
    fi
done
[ "$MCP_COUNT" -eq 0 ] && echo "  ⊘ 无 repo .mcp.json"

# ----------------------------------------------------------------------------
# P1: safe_zone 顶层 hooks（如果 Codex backfill 没覆盖）
# ----------------------------------------------------------------------------
echo "[P1] safe_zone 顶层 hooks..."
if [ -d "$SAFE_ZONE/hooks" ]; then
    mkdir -p "$OUTPUT_DIR/hooks"
    cp -r "$SAFE_ZONE/hooks/"* "$OUTPUT_DIR/hooks/" 2>/dev/null || true
    echo "  ✓ safe_zone/hooks/ 已复制到 $OUTPUT_DIR/hooks/"
fi

# ----------------------------------------------------------------------------
# P1: safe_zone 顶层 skills（如果 Codex backfill 没覆盖的）
# ----------------------------------------------------------------------------
echo "[P1] safe_zone 顶层 skills..."
if [ -d "$SAFE_ZONE/skills" ]; then
    mkdir -p "$OUTPUT_DIR/safe-zone-skills"
    cp -r "$SAFE_ZONE/skills/"* "$OUTPUT_DIR/safe-zone-skills/" 2>/dev/null || true
    echo "  ✓ safe_zone/skills/ 已复制到 $OUTPUT_DIR/safe-zone-skills/"
fi

# ----------------------------------------------------------------------------
# P2: 生成 manifest
# ----------------------------------------------------------------------------
echo ""
echo "[P2] 生成 manifest..."
cat > "$OUTPUT_DIR/backup-manifest.txt" << EOF
备份时间: $TIMESTAMP
输出目录: $OUTPUT_DIR
来源: backup-missing-to-safe-zone.sh v3

包含内容:
EOF
find "$OUTPUT_DIR" -mindepth 1 -maxdepth 2 | sort >> "$OUTPUT_DIR/backup-manifest.txt"
echo "  ✓ manifest: $OUTPUT_DIR/backup-manifest.txt"

# ----------------------------------------------------------------------------
# 完成
# ----------------------------------------------------------------------------
echo ""
echo "========================================"
echo "备份完成"
echo "========================================"
echo "输出目录: $OUTPUT_DIR"
echo ""
echo "建议下一步:"
if [ "$DIRTY_COUNT" -gt 0 ]; then
    echo "  1. 确认所有 repo 已 push（当前 $DIRTY_COUNT 个未提交修改）"
else
    echo "  1. 所有 repo git 干净"
fi
echo "  2. 运行 claude-nuke-and-restore.sh 进行清理和恢复"
