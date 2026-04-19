#!/bin/bash
# ============================================================================
# Claude 完全隔离 + 指纹重置脚本 v3（最终版）
# 目标: 让 Claude 不认识这台电脑
# 修复:
#   - TIMESTAMP 正确定义
#   - Python hook 路径修复用 shlex.split
#   - 不用 find $HOME，改用明确路径列表
#   - 每大类可选执行
#   - 完全隔离导向
# ============================================================================

set -e

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

TIMESTAMP=$(date +%Y%m%d-%H%M%S)

# DRY_RUN=1: 只打印 destructive 命令，不实际执行
DRY_RUN=${DRY_RUN:-0}
if [ "$DRY_RUN" = "1" ]; then
    echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo -e "${BLUE}🔍 DRY-RUN 模式: 所有 destructive 命令只打印不执行${NC}"
    echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
fi

dry() {
    if [ "$DRY_RUN" = "1" ]; then
        echo -e "${BLUE}[DRY-RUN]${NC} $*"
        return 0
    else
        "$@"
    fi
}

clear_chrome_site_storage_live() {
    local cleanup_result

    if ! pgrep -x "Google Chrome" >/dev/null 2>&1; then
        return 1
    fi

    if [ "$DRY_RUN" = "1" ]; then
        echo -e "  ${BLUE}[DRY-RUN]${NC} 会通过 Chrome 自动化清理 claude.ai / console.anthropic.com / www.anthropic.com 的 Local Storage / Session Storage"
        return 0
    fi

    command -v osascript >/dev/null 2>&1 || return 1

    cleanup_result=$(
        osascript 2>/dev/null <<'APPLESCRIPT'
set targetUrls to {"https://claude.ai", "https://console.anthropic.com", "https://www.anthropic.com"}
set createdWindow to false
set cleanupOk to true

tell application "Google Chrome"
    if (count of windows) = 0 then
        make new window
        set createdWindow to true
    end if

    repeat with targetUrl in targetUrls
        set cleanupTab to make new tab at end of tabs of front window with properties {URL:(contents of targetUrl)}
        repeat 40 times
            delay 0.25
            if (loading of cleanupTab is false) then exit repeat
        end repeat
        set jsResult to execute cleanupTab javascript "try { window.localStorage.clear(); window.sessionStorage.clear(); 'ok'; } catch (e) { 'fail'; }"
        if jsResult is not "ok" then set cleanupOk to false
        close cleanupTab
    end repeat

    if createdWindow and (count of tabs of front window) = 1 then
        close front window
    end if
end tell

if cleanupOk then
    return "ok"
else
    error "site storage cleanup incomplete"
end if
APPLESCRIPT
    ) || return 1

    [ "$cleanup_result" = "ok" ]
}

deep_clean_chrome_site_databases() {
    local chrome_base="$HOME/Library/Application Support/Google/Chrome"
    local sqlite_available=false
    local profile

    if command -v sqlite3 >/dev/null 2>&1; then
        sqlite_available=true
    else
        echo -e "  ${YELLOW}⚠️ 未找到 sqlite3，将跳过 Cookie DB 删除，只删除 IndexedDB${NC}"
    fi

    [ -d "$chrome_base" ] || return 0

    for profile in "$chrome_base/Default" "$chrome_base/Profile "*; do
        [ -d "$profile" ] || continue
        dry find "$profile/IndexedDB" -maxdepth 1 \
            \( -name "*claude.ai*.indexeddb.leveldb" -o -name "*claude.ai*.indexeddb.blob" \
               -o -name "*anthropic.com*.indexeddb.leveldb" -o -name "*anthropic.com*.indexeddb.blob" \) \
            -exec rm -rf {} + 2>/dev/null || true
        if [ "$sqlite_available" = true ] && [ -f "$profile/Cookies" ]; then
            dry sqlite3 "$profile/Cookies" \
                "DELETE FROM cookies WHERE host_key LIKE '%claude.ai%' OR host_key LIKE '%anthropic.com%'; PRAGMA wal_checkpoint(TRUNCATE);" \
                2>/dev/null || true
        fi
    done

    dry find "$chrome_base" -name "com.anthropic.claude_browser_extension.json" -delete 2>/dev/null || true
    dry find "$HOME/Library/Application Support/com.openai.atlas" -name "*claude*" -type d -exec rm -rf {} + 2>/dev/null || true
}

# ============================================================================
# 开源版配置读取
# ============================================================================
CONFIG_FILE="${CLAUDEFXXK_CONFIG:-$HOME/.config/claudefxxk/config.sh}"
if [ -f "$CONFIG_FILE" ]; then
    echo -e "${BLUE}ℹ️  读取配置文件: $CONFIG_FILE${NC}"
    # shellcheck source=/dev/null
    source "$CONFIG_FILE"
fi

# 默认值：如果配置文件未定义，设为空数组
[ -z "${SCAN_ROOTS+x}" ]   && declare -a SCAN_ROOTS=()
[ -z "${CLEAN_ROOTS+x}" ]  && declare -a CLEAN_ROOTS=()
[ -z "${MCP_PROJECTS+x}" ] && declare -a MCP_PROJECTS=()

# Warning 累积器
WARNINGS=()
warn() {
    local msg="$1"
    WARNINGS+=("$msg")
    echo -e "${YELLOW}⚠️  $msg${NC}"
}

# 条件变量
MMS_EXISTS=false
CC_SWITCH_EXISTS=false
if pgrep -x "mms" >/dev/null 2>&1; then
    MMS_EXISTS=true
fi
if [ -d "$HOME/.cc-switch" ]; then
    CC_SWITCH_EXISTS=true
fi

# P0: $HOME 虚拟化检测 — 必须在真实终端运行
REAL_HOME=$(eval echo "~$(whoami)")
if [ "$HOME" != "$REAL_HOME" ]; then
    echo -e "${RED}❌ 错误: \$HOME 被虚拟化${NC}"
    echo -e "${YELLOW}   当前 \$HOME: $HOME${NC}"
    echo -e "${YELLOW}   真实 home:   $REAL_HOME${NC}"
    echo -e "${YELLOW}   此脚本必须在真实终端运行，不能在 Claude/MMS session 内执行。${NC}"
    exit 1
fi

: ${SAFE_ZONE:="$HOME/claude_safe_zone"}
: ${CODEX_BF:="$HOME/claude_safe_zone/codex-safe-zone-backfill-20260418"}
if [ -n "$CODEX_BF" ] && [ ! -d "$CODEX_BF" ]; then
    CODEX_BF=""
fi
# P0: 找到最新的 backup-run 目录（backup-missing-to-safe-zone.sh 的输出）
LATEST_BACKUP=$(ls -dt "$SAFE_ZONE"/backup-run-* 2>/dev/null | head -1)
if [ -z "$LATEST_BACKUP" ] && [ -n "$CODEX_BF" ]; then
    echo -e "${YELLOW}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo -e "${YELLOW}⚠️ 未找到 backup-run-* 目录${NC}"
    echo -e "${YELLOW}   建议先运行: ./backup-missing-to-safe-zone.sh${NC}"
    # P0: 列出 safe_zone 顶层实际缺失的资产
    MISSING_ASSETS=""
    [ ! -d "$SAFE_ZONE/plugins" ] && MISSING_ASSETS="$MISSING_ASSETS plugins"
    [ ! -f "$SAFE_ZONE/settings.local.json" ] && MISSING_ASSETS="$MISSING_ASSETS settings.local.json"
    [ ! -f "$SAFE_ZONE/RTK.md" ] && MISSING_ASSETS="$MISSING_ASSETS RTK.md"
    [ ! -d "$SAFE_ZONE/skills" ] && MISSING_ASSETS="$MISSING_ASSETS skills"
    if [ -n "$MISSING_ASSETS" ]; then
        echo -e "${RED}   以下资产在 safe_zone 顶层也不存在，恢复阶段将完全缺失:${NC}"
        echo -e "${RED}   $MISSING_ASSETS${NC}"
    fi
    echo -e "${YELLOW}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo "   当前没有可用的 backup-run 目录。"
    echo "   继续执行不会阻止清理，但恢复阶段可能缺失 settings、plugins 或 skills。"
    echo "   选择: y=带风险继续  N/Enter=退出，先执行备份"
    read -p "仍要继续? [y/N]: " NO_BACKUP_CONTINUE
    [ "$NO_BACKUP_CONTINUE" != "y" ] && [ "$NO_BACKUP_CONTINUE" != "Y" ] && exit 1
fi

echo -e "${RED}"
echo "========================================"
echo "  Claude 完全隔离 + 指纹重置 v3"
echo "========================================"
echo -e "${NC}"
echo "目标: 让 Claude 不认识这台电脑"
echo ""
echo "前置要求:"
echo "  ✅ 已在 Anthropic/MMS 仪表板撤销 Token"
echo "  ✅ git repo 已 push"
echo "  ✅ 已运行 backup-missing-to-safe-zone.sh"
echo ""

echo "从下一步开始将进入清理流程，后续会删除本机上的 Claude 身份文件、缓存和部分痕迹。"
echo "输入 ISOLATE 才会开始；其他任意输入都会取消，且不做任何修改。"
read -p "请输入 [ISOLATE] 开始: " CONFIRM
[ "$CONFIRM" != "ISOLATE" ] && echo "已取消" && exit 0

[ ! -d "$SAFE_ZONE" ] && echo -e "${RED}❌ safe_zone 不存在${NC}" && exit 1

CODEX_EXISTS=false
[ -d "$CODEX_BF" ] && CODEX_EXISTS=true

# P1: 在阶段 2 删除 ~/.claude.json 之前快照 userID，供阶段 16 对比
OLD_USERID=""
if [ -f "$HOME/.claude.json" ]; then
    OLD_USERID=$(python3 -c "import json; d=json.load(open('$HOME/.claude.json')); print(d.get('userID',''))" 2>/dev/null || echo "")
fi

# ============================================================================
# 阶段 0: 前置确认
# ============================================================================
echo ""
echo "========================================"
echo "阶段 0: 前置确认"
echo "========================================"

# P3: 依赖前置检查
echo "[0.0] 依赖检查..."
command -v python3 >/dev/null 2>&1 || { echo -e "${RED}❌ 缺少 python3，阶段 17.6 需要它${NC}"; exit 1; }
echo "  ✓ python3 可用"

# 备份验证
echo ""
echo "[0.1] 备份验证..."
echo "  （备份说明: 每次运行 backup-missing-to-safe-zone.sh 会新增一个 backup-run-YYYYMMDD-HHMMSS/ 目录，不会删除旧备份）"
if [ -n "$LATEST_BACKUP" ]; then
    BACKUP_TIME=$(stat -f "%Sm" "$LATEST_BACKUP" 2>/dev/null || echo "未知")
    echo "  ✓ 找到备份: $(basename "$LATEST_BACKUP")"
    echo "    创建时间: $BACKUP_TIME"
    echo "    内容:"
    [ -f "$LATEST_BACKUP/CLAUDE.md" ] && echo "      ✓ CLAUDE.md"
    [ -d "$LATEST_BACKUP/plugins" ] && echo "      ✓ plugins/"
    [ -f "$LATEST_BACKUP/settings-current-session-sanitized.json" ] && echo "      ✓ settings-current-session-sanitized.json"
    [ -f "$LATEST_BACKUP/settings.local.json" ] && echo "      ✓ settings.local.json"
    [ -d "$LATEST_BACKUP/skills-entity" ] && echo "      ✓ skills-entity/"
    [ -f "$LATEST_BACKUP/skills.symlink-map.txt" ] && echo "      ✓ skills.symlink-map.txt"
    [ -f "$LATEST_BACKUP/RTK.md" ] || echo "      ⊘ RTK.md（缺失，不影响执行）"
    echo "  即将使用 $(basename "$LATEST_BACKUP") 作为恢复源。"
    echo "  如果这不是最新备份，后续可能恢复到旧配置，或漏掉刚新增的资产。"
    echo "  选择: y=确认使用这个备份  N/Enter=退出，先重新备份"
    read -p "  确认使用这个备份? [y/N]: " BACKUP_CONFIRM
    if [ "$BACKUP_CONFIRM" != "y" ] && [ "$BACKUP_CONFIRM" != "Y" ]; then
        echo "  → 请重新运行 ./backup-missing-to-safe-zone.sh 后再执行本脚本"
        exit 1
    fi
else
    echo -e "  ${RED}❌ 未找到 backup-run-* 目录${NC}"
    if [ "$DRY_RUN" = "1" ]; then
        echo -e "  ${BLUE}[DRY-RUN]${NC} 跳过自动备份，继续流程"
    else
        echo "  将自动执行备份脚本..."
        SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
        "$SCRIPT_DIR/backup-missing-to-safe-zone.sh"
        LATEST_BACKUP=$(ls -dt "$SAFE_ZONE"/backup-run-* 2>/dev/null | head -1)
        if [ -z "$LATEST_BACKUP" ]; then
            echo -e "${RED}❌ 备份失败，退出${NC}"
            exit 1
        fi
        echo "  ✓ 备份完成: $(basename "$LATEST_BACKUP")"
    fi
fi

echo ""
echo "[0.2] API key 检查..."
echo "  如果你用过 Claude API key（类似 sk-xxx 的密钥），建议先删除。"
echo "  只用过浏览器 OAuth 登录的用户没有 API key，直接选 y。"
echo "  这一步只是前置确认，不会修改本机文件。"
echo "  选择: y=已确认处理完成  N/Enter=退出"
read -p "  API key 已处理完成? [y/N]: " TOKEN_OK
[ "$TOKEN_OK" != "y" ] && [ "$TOKEN_OK" != "Y" ] && exit 1

echo "[0.3] 关键 repo 检查..."
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
[ "$DIRTY_COUNT" -gt 0 ] && echo -e "${YELLOW}   共 $DIRTY_COUNT 个未提交修改${NC}"

# MCP_PROJECTS 路径存在性预检
for proj in "${MCP_PROJECTS[@]}"; do
    [ -d "$proj" ] || warn "MCP_PROJECTS 路径不存在: $proj"
done

# ============================================================================
# 阶段 1: 杀进程
# ============================================================================
echo ""
echo "========================================"
echo "阶段 1: 杀进程"
echo "========================================"
# 精确匹配进程名，避免误杀含 claude 的其他进程（如 codex-watcher）
# MMS 工作保存确认 + 进程展示
echo ""
if [ "$MMS_EXISTS" = true ]; then
    echo "[0.4] 进程检查 & MMS 工作保存确认..."
else
    echo "[0.4] 进程检查..."
fi
echo "  ──────────────────────────────"

# 检查进程是否是 MMS 子进程
is_mms_child() {
    local pid=$1
    local p=$pid
    while [ -n "$p" ] && [ "$p" != "1" ]; do
        local ppid=$(ps -p "$p" -o ppid= 2>/dev/null | tr -d ' ')
        local pname=$(ps -p "$ppid" -o comm= 2>/dev/null | tr -d ' ')
        if [ "$pname" = "mms" ]; then
            return 0
        fi
        p=$ppid
    done
    return 1
}

# --- Claude CLI (claude) ---
CL_PIDS=$(pgrep -x "claude" 2>/dev/null) || true
CL_INDEP=0
CL_MMS=0
for cpid in $CL_PIDS; do
    [ -z "$cpid" ] && continue
    if is_mms_child "$cpid"; then
        CL_MMS=$((CL_MMS + 1))
    else
        CL_INDEP=$((CL_INDEP + 1))
    fi
done

if [ "$CL_INDEP" -gt 0 ]; then
    echo "  • 独立 Claude CLI: $CL_INDEP 个 [阶段1会被终止]"
    for cpid in $CL_PIDS; do
        [ -z "$cpid" ] && continue
        if ! is_mms_child "$cpid"; then
            ctt=$(ps -p "$cpid" -o tty= 2>/dev/null | tr -d ' ')
            args=$(ps -p "$cpid" -o args= 2>/dev/null | head -c 70)
            echo "      PID $cpid (terminal: $ctt)"
            echo "        └─ $args"
        fi
    done
fi
if [ "$CL_MMS" -gt 0 ]; then
    echo "  • MMS 启动的 Claude/Codex CLI: $CL_MMS 个 [阶段1会被终止]"
    for cpid in $CL_PIDS; do
        [ -z "$cpid" ] && continue
        if is_mms_child "$cpid"; then
            ctt=$(ps -p "$cpid" -o tty= 2>/dev/null | tr -d ' ')
            args=$(ps -p "$cpid" -o args= 2>/dev/null | head -c 70)
            echo "      PID $cpid (terminal: $ctt) [MMS子进程]"
            echo "        └─ $args"
        fi
    done
fi

# --- claude-code ---
CC_PIDS=$(pgrep -x "claude-code" 2>/dev/null) || true
CC_INDEP=0
CC_MMS=0
for cpid in $CC_PIDS; do
    [ -z "$cpid" ] && continue
    if is_mms_child "$cpid"; then
        CC_MMS=$((CC_MMS + 1))
    else
        CC_INDEP=$((CC_INDEP + 1))
    fi
done
if [ "$CC_INDEP" -gt 0 ]; then
    echo "  • 独立 claude-code: $CC_INDEP 个 [阶段1会被终止]"
    for cpid in $CC_PIDS; do
        [ -z "$cpid" ] && continue
        if ! is_mms_child "$cpid"; then
            ctt=$(ps -p "$cpid" -o tty= 2>/dev/null | tr -d ' ')
            args=$(ps -p "$cpid" -o args= 2>/dev/null | head -c 70)
            echo "      PID $cpid (terminal: $ctt)"
            echo "        └─ $args"
        fi
    done
fi
if [ "$CC_MMS" -gt 0 ]; then
    echo "  • MMS 启动的 claude-code: $CC_MMS 个 [阶段1会被终止]"
    for cpid in $CC_PIDS; do
        [ -z "$cpid" ] && continue
        if is_mms_child "$cpid"; then
            ctt=$(ps -p "$cpid" -o tty= 2>/dev/null | tr -d ' ')
            args=$(ps -p "$cpid" -o args= 2>/dev/null | head -c 70)
            echo "      PID $cpid (terminal: $ctt) [MMS子进程]"
            echo "        └─ $args"
        fi
    done
fi

# --- Claude Desktop ---
CD_COUNT=$(pgrep -x "Claude" 2>/dev/null | wc -l | tr -d ' ')
[ "$CD_COUNT" -gt 0 ] && echo "  • Claude Desktop: $CD_COUNT 个 [阶段1会被终止]"

# --- MMS 主进程 ---
MMS_COUNT=0
if [ "$MMS_EXISTS" = true ]; then
    MMS_COUNT=$(pgrep -f "mms$" 2>/dev/null | wc -l | tr -d ' ')
    if [ "$MMS_COUNT" -gt 0 ]; then
        echo "  • MMS 主进程: $MMS_COUNT 个 [保留，不会被终止]"
        for mpid in $(pgrep -f "mms$" 2>/dev/null | tr '\n' ' '); do
            [ -z "$mpid" ] && continue
            mtt=$(ps -p "$mpid" -o tty= 2>/dev/null | tr -d ' ')
            [ -n "$mtt" ] && echo "      PID $mpid (terminal: $mtt)"
        done
    fi
fi

# --- Chrome ---
CHROME_COUNT=$(pgrep -x "Google Chrome" 2>/dev/null | wc -l | tr -d ' ')
[ "$CHROME_COUNT" -gt 0 ] && echo "  • Chrome: 正在运行（阶段 8 可选关闭）"

# 无进程提示
TOTAL_CLAUDE=$((CL_INDEP + CL_MMS + CC_INDEP + CC_MMS + CD_COUNT))
[ "$TOTAL_CLAUDE" -eq 0 ] && [ "$MMS_COUNT" -eq 0 ] && echo "  • 无 Claude/MMS 进程在运行"

echo "  ──────────────────────────────"
echo ""
echo "  ⚠️  阶段 1 会终止所有 Claude / claude / claude-code 进程。"
if [ "$MMS_EXISTS" = true ]; then
    echo "     MMS 主进程(mms)保留。MMS 配置(~/.config/mms/)保留。"
    echo "     终止后可在 MMS 中重新连接/启动 session，不会丢失 MMS session 配置。"
fi
echo "  选择: y=我已保存，可以继续  N/Enter=退出"
read -p "  是否继续终止 Claude 相关进程? [y/N]: " MMS_SAVED
[ "$MMS_SAVED" != "y" ] && [ "$MMS_SAVED" != "Y" ] && exit 1

# 1) 先杀 Desktop App 子进程（必须在主进程之前，否则 pgrep 拿不到 PID）
for desktop_pid in $(pgrep -x "Claude" 2>/dev/null | tr '\n' ' '); do
    [ -z "$desktop_pid" ] && continue
    dry pkill -9 -P "$desktop_pid" 2>/dev/null || true
done

# 2) 再杀主进程
dry pkill -9 -x "Claude" 2>/dev/null || true
dry pkill -9 -x "claude" 2>/dev/null || true
dry pkill -9 -x "claude-code" 2>/dev/null || true

# 3) 兜底：按路径匹配 CLI 进程（避免误杀 hive 等含 "claude" 的进程）
dry pkill -9 -f "\.local/bin/claude" 2>/dev/null || true
dry pkill -9 -f "claude-code/dist" 2>/dev/null || true

echo "  ✓ 已终止"
sleep 2

# ============================================================================
# 阶段 2: 核心身份文件（必选）
# ============================================================================
echo ""
echo "========================================"
echo "阶段 2: 核心身份文件"
echo "========================================"
dry rm -f "$HOME/.claude.json" "$HOME/.claude.json.backup" "$HOME/.claude.json.backup."* "$HOME/.claude.json.bak"*
# 备份 .claude.bak 到项目目录后再清理
    BACKUP_DIR="$HOME/claude_safe_zone/backups/backup-$TIMESTAMP"
    dry mkdir -p "$BACKUP_DIR"
    [ -d "$HOME/.claude.bak" ] && dry mv "$HOME/.claude.bak" "$BACKUP_DIR/" && echo "  → .claude.bak 已备份到 $BACKUP_DIR"
    dry rm -rf "$HOME/.claude"
    # 精细化清理 ~/.cc-switch — 只删敏感数据（db/logs/backups），保留配置和 skills
    if [ "$CC_SWITCH_EXISTS" = true ]; then
        dry rm -rf "$HOME/.cc-switch/logs" "$HOME/.cc-switch/backups"
        dry rm -f "$HOME/.cc-switch/cc-switch.db" "$HOME/.cc-switch/cc-switch2.db"
        echo "  ✓ ~/.cc-switch 敏感数据已清除（保留 settings.json、skills、skills-review.md）"
    fi
echo "  ✓ ~/.claude.json / ~/.claude 已清除（.claude.bak 已备份）"

# ============================================================================
# 阶段 3: Keychain（必选）
# ============================================================================
echo ""
echo "========================================"
echo "阶段 3: Keychain 凭证"
echo "========================================"
for key in "Claude Safe Storage" "Claude Code-credentials" "Claude Code-credentials-e549de00" "claude-code" "claude-code-credentials"; do
    dry security delete-generic-password -s "$key" 2>/dev/null || true
    dry security delete-generic-password -s "$key" -a "Claude" 2>/dev/null || true
    dry security delete-generic-password -s "$key" -a "Claude Key" 2>/dev/null || true
    dry security delete-generic-password -s "$key" -a "xin" 2>/dev/null || true
    dry security delete-generic-password -s "$key" -a "unknown" 2>/dev/null || true
done
KC_RESIDUE=$(security dump-keychain 2>/dev/null | grep -ic "claude" || true)
[ -z "$KC_RESIDUE" ] && KC_RESIDUE=0
[ "$KC_RESIDUE" -gt 0 ] && echo -e "  ${YELLOW}⚠ Keychain 仍有 $KC_RESIDUE 条残留，请手动检查${NC}" || echo "  ✓ Keychain 已清理"

# ============================================================================
# 阶段 4-8: 可选大类（每类单独确认）
# ============================================================================

run_phase() {
    local num="$1" name="$2" desc="$3"
    echo ""
    echo "========================================"
    echo "阶段 $num: $name"
    echo "========================================"
    echo "  这一步会: $desc"
    echo "  选择: y=执行此阶段  N/Enter=跳过此阶段"
    read -p "  是否执行阶段 $num? [y/N]: " OK
    if [ "$OK" = "y" ] || [ "$OK" = "Y" ]; then
        return 0
    fi
    echo "  ⊘ 已跳过阶段 $num"
    return 1
}

# --- 4: Desktop App ---
if run_phase "4" "Desktop App 数据" "删除 Claude Desktop 的本地数据与缓存；不会删除 App 本体"; then
    dry rm -rf "$HOME/Library/Application Support/Claude"
    dry rm -rf "$HOME/Library/Caches/com.anthropic.claudefordesktop"*
    dry rm -rf "$HOME/Library/HTTPStorages/com.anthropic.claudefordesktop"
    dry rm -f "$HOME/Library/Preferences/com.anthropic.claudefordesktop.plist"
    dry rm -f "$HOME/Library/Preferences/ByHost/com.anthropic.claudefordesktop.ShipIt"*.plist
    dry rm -rf "$HOME/Library/Logs/Claude"
    dry rm -rf "$HOME/Library/Saved Application State/com.anthropic.claudefordesktop.savedState"
    dry rm -rf "$HOME/Library/WebKit/com.anthropic.claudefordesktop"
    dry defaults delete com.anthropic.claudefordesktop 2>/dev/null || true
    echo "  ✓ Desktop App 数据已清除"
fi

# --- 5: CLI 安装物 ---
if run_phase "5" "CLI 安装物" "删除 Claude CLI 的安装物与本地缓存；后续如需使用需要重新安装"; then
    dry rm -f "$HOME/.local/bin/claude" "$HOME/.local/bin/claude.bak"*
    dry rm -rf "$HOME/.local/share/claude" "$HOME/.local/state/claude" "$HOME/.cache/claude"
    dry rm -rf "$HOME/Library/Caches/claude-cli-nodejs"
    dry npm uninstall -g claude-talk-to-figma-mcp 2>/dev/null || true
    echo "  ✓ CLI 安装物已清除"
fi

# --- 6: IDE 扩展 ---
if run_phase "6" "IDE 扩展" "删除 VS Code / Zed 中的 Claude 扩展与相关日志；不会修改项目源码"; then
    dry rm -rf "$HOME/.vscode/extensions/anthropic.claude-code-"*
    dry rm -rf "$HOME/Library/Application Support/Code/logs/"*/"window"*"/exthost/Anthropic.claude-code"
    dry rm -rf "$HOME/Library/Application Support/Code/CachedExtensionVSIXs/anthropic.claude-code-"*
    dry rm -rf "$HOME/Library/Application Support/Zed/external_agents/claude-code-acp"
    echo "  ✓ IDE 扩展已清除"
fi

# --- 7: MMS/MMC 网关层 ---
if run_phase "7" "MMS/MMC 网关层" "删除 MMS/MMC 中的 Claude 身份与会话状态；保留 bridge 元数据和 mms 主配置"; then
    for f in "$HOME/.config/mms/claude-gateway/s"/*/.claude.json; do [ -f "$f" ] && dry rm -f "$f"; done
    for d in "$HOME/.config/mms/claude-gateway/s"/*/.claude; do [ -d "$d" ] && dry rm -rf "$d"; done
    # P1: 只删 session 内的 Claude 状态目录，不动 bridge 元数据（.mms_slot.json 等）
    for sd in "$HOME/.config/mms/claude-gateway/s"/*; do
        [ -d "$sd" ] || continue
        dry rm -rf "$sd/.claude" 2>/dev/null || true
        dry rm -f "$sd/.claude.json" 2>/dev/null || true
    done
    dry rm -f "$HOME/.config/mms/claude-gateway/.claude.json"
    dry rm -rf "$HOME/.config/mms/claude-gateway/.claude"
    for ad in "$HOME/.config/mms/accounts/"*; do
        [ -d "$ad" ] || continue
        dry rm -f "$ad/.claude.json" 2>/dev/null || true
        dry rm -rf "$ad/.claude" 2>/dev/null || true
    done
    dry rm -rf "$HOME/.config/mms/accounts-archived" "$HOME/.config/mms-backups" "$HOME/.mms/token_cache"
    dry rm -f "$HOME/.config/mms/events/"*.jsonl "$HOME/.config/mms/config-audit.jsonl"
    for raw in "$HOME/.config/mms/projects"/*/claude/raw; do
        [ -d "$raw" ] || continue
        dry rm -rf "$raw/sessions" "$raw/transcripts" "$raw/file-history" 2>/dev/null || true
        dry rm -f "$raw/history.jsonl" 2>/dev/null || true
    done
    dry rm -f "$HOME/.config/mmc/accounts/default/.claude.json"
    dry rm -rf "$HOME/.config/mmc/accounts/default/.claude"
    echo "  ✓ MMS/MMC 已清除"
fi

# --- 8: 浏览器数据 ---
if run_phase "8" "浏览器数据" "默认先轻清理 Chrome 中 claude.ai / anthropic.com 的 Local Storage / Session Storage；若你在安全关闭 Chrome 后确认，还可进一步删除 IndexedDB / Cookie DB（风险更高）"; then
    if pgrep -x "Google Chrome" >/dev/null 2>&1; then
        echo "  先执行默认轻清理：Local Storage / Session Storage"
        echo "  这一步会通过当前活跃的 Chrome profile 清理 claude.ai / anthropic.com 的前端站点状态。"
        echo "  它不会直接改写 IndexedDB / Cookie DB，通常比直接改 profile 数据库更稳。"
        if clear_chrome_site_storage_live; then
            echo "  ✓ 已尝试清理当前活跃 profile 的 Local Storage / Session Storage"
        else
            echo -e "  ${YELLOW}⚠️ 未能通过 Chrome 自动化清理 Local Storage / Session Storage${NC}"
            echo "    可能是浏览器自动化权限未授权，或目标站点未能正常加载。"
        fi
    else
        echo "  Chrome 当前未运行。Session Storage 会随浏览器退出自然释放。"
        echo "  Local Storage 的定向轻清理依赖浏览器上下文，本次不会自动清它。"
        echo "  如果你也想清 Local Storage，请先启动 Chrome，再重跑这一阶段。"
    fi

    echo ""
    echo "  当前默认不会直接删除的深度站点数据："
    echo "    - IndexedDB: 站点持久缓存、草稿、最近状态可能仍保留"
    echo "    - Cookie DB: OAuth / 登录态 Cookie 可能仍保留"
    echo "  如果继续删除它们，清理会更彻底，但也更容易触发 Chrome 首次启动卡顿或 profile 恢复。"
    read -p "  按 Enter 继续，决定是否做深度清理..."

    if pgrep -x "Google Chrome" >/dev/null 2>&1; then
        echo -e "  ${YELLOW}⚠️ 当前仍检测到 Chrome 在运行${NC}"
    fi

    read -p "  Chrome 是否已经安全关闭? [y/N]: " CHROME_SAFE_CLOSED
    if [ "$CHROME_SAFE_CLOSED" = "y" ] || [ "$CHROME_SAFE_CLOSED" = "Y" ]; then
        if pgrep -x "Google Chrome" >/dev/null 2>&1; then
            echo -e "  ${YELLOW}⚠️ Chrome 仍在运行，跳过 IndexedDB / Cookie DB 清理${NC}"
            echo "    请先完全退出 Chrome，再重新执行阶段 8 的深度清理。"
        else
            echo "  即将删除："
            echo "    - claude.ai / anthropic.com 的 IndexedDB"
            echo "    - claude.ai / anthropic.com 的 Cookie DB 记录"
            echo "    - Claude browser extension bridge / Atlas 中的 claude 元数据"
            echo -e "  ${YELLOW}⚠️ 风险：这一步更彻底，但可能引起 Chrome 首次启动卡顿、站点缓存重建或 profile 恢复${NC}"
            read -p "  是否继续删除 IndexedDB / Cookie DB? [y/N]: " DEEP_CHROME_CLEAN
            if [ "$DEEP_CHROME_CLEAN" = "y" ] || [ "$DEEP_CHROME_CLEAN" = "Y" ]; then
                deep_clean_chrome_site_databases
                echo "  ✓ IndexedDB / Cookie DB 已按确认执行深度清理"
            else
                echo "  ⊘ 已跳过 IndexedDB / Cookie DB 深度清理"
            fi
        fi
    else
        echo "  ⊘ 已跳过 IndexedDB / Cookie DB 深度清理"
    fi
fi

# --- 9: /tmp ---
if run_phase "9" "/tmp 临时文件" "删除 /tmp 下已知的 Claude 临时文件"; then
    dry rm -rf /tmp/claude-501
    dry rm -f /tmp/claude_doc.md /tmp/claude-ban-investigation.md /tmp/claude-socks-bridge.service.new
    dry rm -rf /tmp/hive-*-.claude /tmp/us-cpa-migrate-20260415
    dry find /tmp -maxdepth 1 -name "claude-*" -exec rm -rf {} + 2>/dev/null || true
    echo "  ✓ /tmp 已清理"
fi

# --- 10: 项目级 .claude/ ---
if run_phase "10" "项目级 .claude/ 追踪数据" "删除 SCAN_ROOTS/CLEAN_ROOTS 中项目目录的 .claude 会话痕迹"; then
    if [ ${#CLEAN_ROOTS[@]} -eq 0 ]; then
        echo -e "  ${YELLOW}⚠️  CLEAN_ROOTS 未配置，跳过项目级 .claude 清理${NC}"
        echo "     如需清理，在 ~/.config/claudefxxk/config.sh 中设置:"
        echo "       CLEAN_ROOTS=(\"\$HOME/project-a\" \"\$HOME/project-b\")"
    else
        for base in "${CLEAN_ROOTS[@]}"; do
            [ -d "$base" ] || { warn "CLEAN_ROOTS 路径不存在: $base"; continue; }
            dry find "$base" -maxdepth 3 -path "*/.claude/sessions" -type d -exec rm -rf {} + 2>/dev/null || true
            dry find "$base" -maxdepth 3 -path "*/.claude/transcripts" -type d -exec rm -rf {} + 2>/dev/null || true
            dry find "$base" -maxdepth 3 -path "*/.claude/file-history" -type d -exec rm -rf {} + 2>/dev/null || true
            dry find "$base" -maxdepth 3 -name "history.jsonl" -path "*/.claude/*" -delete 2>/dev/null || true
        done
        echo "  ✓ 配置的项目中的追踪数据已清理"
    fi
fi

# --- 11: Desktop App 本体 + URL Handler ---
if run_phase "11" "Desktop App 本体" "删除 Claude Desktop App 本体与 Claude Code URL Handler"; then
    dry rm -rf "/Applications/Claude.app" "$HOME/Applications/Claude Code URL Handler.app"
    echo "  ✓ Desktop App 已删除"
fi

# --- 12: shell history ---
if run_phase "12" "shell history" "按 best-effort 清理 .zsh_history / .bash_history 中的 claude 记录"; then
    echo -e "  ${YELLOW}⚠️ 注意：此操作只修改 .zsh_history / .bash_history 文件，不会关闭当前窗口${NC}"
    echo -e "  ${YELLOW}   但建议先关闭其他 Terminal/zsh 窗口，避免 concurrent write${NC}"
    echo "  按 Enter 继续；输入 s 可跳过本阶段。"
    read -p "  继续清理 history? [Enter=继续 / s=跳过]: " HISTORY_CONFIRM
    if [ "$HISTORY_CONFIRM" = "s" ] || [ "$HISTORY_CONFIRM" = "S" ]; then
        echo "  ⊘ 已跳过 history 清理"
    else
        dry cp "$HOME/.zsh_history" "$HOME/.zsh_history.backup-$TIMESTAMP" 2>/dev/null || true
        dry cp "$HOME/.bash_history" "$HOME/.bash_history.backup-$TIMESTAMP" 2>/dev/null || true
        # LC_ALL=C 保证非 ASCII 字符不乱码（bash 无法 flush 其他 zsh session，best-effort）
        if [ "$DRY_RUN" != "1" ]; then
            if LC_ALL=C grep -iv "claude" "$HOME/.zsh_history" > "$HOME/.zsh_history.tmp" 2>/dev/null; then
                dry mv "$HOME/.zsh_history.tmp" "$HOME/.zsh_history"
            else
                dry rm -f "$HOME/.zsh_history.tmp"
            fi
            if LC_ALL=C grep -iv "claude" "$HOME/.bash_history" > "$HOME/.bash_history.tmp" 2>/dev/null; then
                dry mv "$HOME/.bash_history.tmp" "$HOME/.bash_history"
            else
                dry rm -f "$HOME/.bash_history.tmp"
            fi
        else
            echo -e "${BLUE}[DRY-RUN]${NC} grep 清理 .zsh_history / .bash_history（跳过，不创建 .tmp 文件）"
        fi
        echo "  ✓ history 已清理（best-effort，如有其他 zsh 存活可能写回）"
    fi
fi

# --- 13: .zshrc 中的 claude 函数 ---
if run_phase "13" ".zshrc 函数" "从 .zshrc 中删除 claudefxxk proxy marker 块"; then
    dry cp "$HOME/.zshrc" "$HOME/.zshrc.backup-$TIMESTAMP"
    echo "  → .zshrc 已备份到 $HOME/.zshrc.backup-$TIMESTAMP"
    if [ "$DRY_RUN" != "1" ]; then
        awk '
            /^# >>> claudefxxk proxy/ { skip=1; next }
            /^# <<< claudefxxk proxy/ { skip=0; next }
            skip { next }
            { print }
        ' "$HOME/.zshrc" > "$HOME/.zshrc.tmp" && mv "$HOME/.zshrc.tmp" "$HOME/.zshrc"
    else
        echo -e "${BLUE}[DRY-RUN]${NC} awk 删除 .zshrc 中的 claudefxxk proxy marker 块"
    fi
    echo "  ✓ .zshrc 已清理"
fi

# --- 14: git config email ---
CURRENT_EMAIL=$(git config --global user.email 2>/dev/null | tr -cd '[:alnum:]@._-+' | head -c 100)
[ -z "$CURRENT_EMAIL" ] && CURRENT_EMAIL="未设置"
if run_phase "14" "git config email" "可选修改 git global user.email；直接回车保持不变"; then
    echo "  推荐匿名地址: user-$(date +%Y%m%d)@example.com"
    echo "  当前 global git email: $CURRENT_EMAIL"
    echo "  直接回车 = 保持不变；输入新的 email = 立即写入 git config --global user.email"
    read -p "  新的 git user.email: " NEW_EMAIL
    if [ -z "$NEW_EMAIL" ] || [ "$NEW_EMAIL" = "n" ] || [ "$NEW_EMAIL" = "N" ]; then
        echo "  ⊘ 跳过，保持当前 email: $CURRENT_EMAIL"
    else
        dry git config --global user.email "$NEW_EMAIL" && echo "  ✓ git email 已改为 $NEW_EMAIL"
    fi
fi

# ============================================================================
# 阶段 15: 重新安装 CLI
# ============================================================================
echo ""
echo "========================================"
echo "阶段 15: 重新安装 Claude Code CLI"
echo "========================================"
echo "  这一步只安装 Claude Code CLI，不会自动登录账号。"
echo "  1) npm install -g @anthropic-ai/claude-code"
echo "  2) 跳过"
read -p "选择 [1/2]（Enter=2）: " INSTALL
if [ "$INSTALL" = "1" ]; then
    dry npm install -g @anthropic-ai/claude-code || { echo -e "${RED}❌ npm install 失败${NC}"; exit 1; }
    echo "  ✓ npm 安装完成"
else
    echo "  ⊘ 跳过"
fi

# ============================================================================
# 阶段 16: 首次启动验证（强制）
# ============================================================================
echo ""
echo "========================================"
echo "阶段 16: 首次启动验证"
echo "========================================"

# 显示执行前保存的 userID（在阶段 2 删除 ~/.claude.json 之前已快照）
if [ -n "$OLD_USERID" ]; then
    echo "  执行前 userID: ${OLD_USERID:0:16}..."
else
    echo "  执行前 userID: 未记录（阶段2已清理或文件不存在）"
fi

echo ""
echo "请新开一个 Terminal 窗口，运行 'claude'，确认："
echo "  1. 必须弹出完整浏览器 OAuth 页面"
echo "  2. 如果直接进入聊天 = 清理失败"
echo "  3. ~/.claude.json 会生成新的 userID"
echo ""
echo "验证完成后回到此窗口回答："
echo "  选择: y=已看到 OAuth 页面  N/Enter=退出，保留当前状态供排查"
read -p "已新开窗口运行 claude 并看到 OAuth 弹窗? [y/N]: " OAUTH_OK
[ "$OAUTH_OK" != "y" ] && [ "$OAUTH_OK" != "Y" ] && echo -e "${RED}⚠ 清理可能失败，请检查残留${NC}" && exit 1

# 自动对比 userID
echo ""
echo "  自动检查 ~/.claude.json userID 变化..."
if [ "$DRY_RUN" = "1" ]; then
    echo -e "  ${BLUE}[DRY-RUN]${NC} 跳过对比（DRY_RUN 未实际清理 ~/.claude.json）"
else
    if [ -f "$HOME/.claude.json" ]; then
        NEW_USERID=$(python3 -c "import json; d=json.load(open('$HOME/.claude.json')); print(d.get('userID',''))" 2>/dev/null || echo "")
        if [ -n "$NEW_USERID" ]; then
            if [ -n "$OLD_USERID" ]; then
                if [ "$NEW_USERID" = "$OLD_USERID" ]; then
                    echo -e "  ${YELLOW}⚠️  userID 未变化 (${NEW_USERID:0:16}...) — 可能清理不完全${NC}"
                    echo "    建议：检查 ~/.claude.json 残留、Keychain 未清、或浏览器 cookie 未清"
                else
                    echo -e "  ${GREEN}✓ userID 已更新${NC}"
                    echo "    旧 ID: ${OLD_USERID:0:16}..."
                    echo "    新 ID: ${NEW_USERID:0:16}..."
                fi
            else
                echo -e "  ${GREEN}✓ 已检测到新的 userID${NC}"
                echo "    执行前未记录到旧 ID，本次无法做旧/新对比"
                echo "    新 ID: ${NEW_USERID:0:16}..."
            fi
        else
            echo -e "  ${YELLOW}⚠️  ~/.claude.json 中未找到 userID${NC}"
        fi
    else
        echo -e "  ${YELLOW}⚠️  ~/.claude.json 不存在 — Claude 尚未生成身份文件${NC}"
    fi
fi

# ============================================================================
# 阶段 17: 恢复资产（白名单方式）
# ============================================================================
echo ""
echo "========================================"
echo "阶段 17: 恢复自定义资产"
echo "========================================"

# P0: 先确保 ~/.claude 目录存在（阶段 2 已删除）
dry mkdir -p "$HOME/.claude" "$HOME/.claude/plugins" "$HOME/.claude/skills" "$HOME/.claude/hooks" "$HOME/.claude/read-once"

# 17.1 CLAUDE.md — 优先从最新备份恢复，再 fallback
CLAUDE_SRC=""
for src in "$LATEST_BACKUP/CLAUDE.md" "$CODEX_BF/templates/CLAUDE.global.md" "$SAFE_ZONE/CLAUDE.md"; do
    [ -f "$src" ] && CLAUDE_SRC="$src" && break
done
if [ -n "$CLAUDE_SRC" ]; then
    dry cp "$CLAUDE_SRC" "$HOME/.claude/CLAUDE.md"
    echo "  ✓ CLAUDE.md (from $(basename $(dirname "$CLAUDE_SRC")))"
fi

# 17.2 Plugins
PLUGIN_SRC=""
for src in "$LATEST_BACKUP/plugins" "$SAFE_ZONE/plugins"; do
    [ -d "$src" ] && PLUGIN_SRC="$src" && break
done
if [ -n "$PLUGIN_SRC" ]; then
    dry mkdir -p "$HOME/.claude/plugins"
    if [ "$(ls -A "$PLUGIN_SRC" 2>/dev/null | wc -l | tr -d ' ')" -gt 0 ]; then
        dry cp -r "$PLUGIN_SRC/"* "$HOME/.claude/plugins/" 2>/dev/null || true
        echo "  ✓ Plugins"
    else
        echo -e "  ${YELLOW}⚠️ Plugins 源目录为空，跳过${NC}"
    fi
fi

# 17.3 Skills
dry mkdir -p "$HOME/.claude/skills"
for src in "$LATEST_BACKUP/skills-entity" "$SAFE_ZONE/skills" "$SAFE_ZONE/skills-bak-entities"; do
    if [ -d "$src" ] && [ "$(ls -A "$src" 2>/dev/null | wc -l | tr -d ' ')" -gt 0 ]; then
        dry cp -r "$src/"* "$HOME/.claude/skills/" 2>/dev/null || true
    fi
done
if [ "$CODEX_EXISTS" = true ] && [ -d "$CODEX_BF/entity-skills-from-claude-bak" ]; then
    if [ "$(ls -A "$CODEX_BF/entity-skills-from-claude-bak" 2>/dev/null | wc -l | tr -d ' ')" -gt 0 ]; then
        dry cp -r "$CODEX_BF/entity-skills-from-claude-bak/"* "$HOME/.claude/skills/" 2>/dev/null || true
    fi
fi
# symlink 重建 — 优先从最新备份读取 map（必须至少有一行非注释内容）
symlink_map_valid() { [ -f "$1" ] && grep -v '^[[:space:]]*#' "$1" 2>/dev/null | grep -q '[^[:space:]]'; }
SYMLINK_MAP=""
symlink_map_valid "$LATEST_BACKUP/skills.symlink-map.txt" && SYMLINK_MAP="$LATEST_BACKUP/skills.symlink-map.txt"
[ -z "$SYMLINK_MAP" ] && symlink_map_valid "$CODEX_BF/templates/skills.symlink-map.txt" && SYMLINK_MAP="$CODEX_BF/templates/skills.symlink-map.txt"
[ -z "$SYMLINK_MAP" ] && symlink_map_valid "$SAFE_ZONE/symlink-map-all.txt" && SYMLINK_MAP="$SAFE_ZONE/symlink-map-all.txt"
if [ -n "$SYMLINK_MAP" ]; then
    cd "$HOME/.claude/skills"
    while IFS= read -r line; do
        [[ "$line" =~ ^#.*$ ]] && continue
        [[ -z "$line" ]] && continue
        skill_name=$(echo "$line" | awk '{print $1}' | sed 's|/$||')
        target=$(echo "$line" | awk '{print $3}')
        [ -z "$skill_name" ] || [ -z "$target" ] && continue
        target="${target/#\~/$HOME}"
        [ ! -e "$skill_name" ] && dry ln -s "$target" "$skill_name" 2>/dev/null && echo "    ✓ symlink $skill_name"
    done < "$SYMLINK_MAP"
fi

# 17.4 Hooks
dry mkdir -p "$HOME/.claude/hooks" "$HOME/.claude/read-once"
HOOKS_RESTORED=false
for f in "$SAFE_ZONE/hooks/"*.sh; do
    [ -f "$f" ] && dry cp "$f" "$HOME/.claude/hooks/" && HOOKS_RESTORED=true
done
for f in "$LATEST_BACKUP/hooks/"*.sh; do
    [ -f "$f" ] && dry cp "$f" "$HOME/.claude/hooks/" && HOOKS_RESTORED=true
done
if [ "$HOOKS_RESTORED" = true ]; then
    echo "  ✓ Hooks (from backup/safe_zone)"
else
    echo -e "  ${YELLOW}⚠️  未找到 hooks 备份；如需恢复，请先运行 backup-missing-to-safe-zone.sh${NC}"
fi

# 17.5 Settings.json（优先最新备份的脱敏版，再 fallback 内置模板）
SETTINGS_JSON_SRC=""
for src in "$LATEST_BACKUP/settings-current-session-sanitized.json" "$SAFE_ZONE/settings.json"; do
    [ -f "$src" ] && SETTINGS_JSON_SRC="$src" && break
done
if [ -n "$SETTINGS_JSON_SRC" ]; then
    dry cp "$SETTINGS_JSON_SRC" "$HOME/.claude/settings.json"
    echo "  ✓ settings.json (from $(basename "$SETTINGS_JSON_SRC"))"
else
    # fallback: 使用内置通用模板
    if [ "$DRY_RUN" != "1" ]; then
        SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
        if [ -f "$SCRIPT_DIR/../templates/settings.json" ]; then
            cp "$SCRIPT_DIR/../templates/settings.json" "$HOME/.claude/settings.json"
        else
            cat > "$HOME/.claude/settings.json" << 'JSONEOF'
{
  "permissions": {
    "allow": ["Read", "Edit", "Write", "Bash(yarn *)", "Bash(npm *)", "Bash(node *)", "Bash(git *)", "Bash(ls *)", "Bash(cat *)", "Bash(find *)", "Bash(grep *)", "Bash(which *)", "Bash(chmod *)", "Bash(cd *)", "Bash(python3 *)", "Bash(rsync *)", "Skill(*)", "Agent(*)"],
    "deny": ["Bash(rm -rf /)*", "Bash(git push --force *)"],
    "defaultMode": "bypassPermissions"
  },
  "statusLine": {
    "type": "command",
    "command": "/bin/bash -c 'echo \"[Claude] $(date +%H:%M:%S) | $(whoami)@$(hostname -s)\"'"
  },
  "hooks": {},
  "promptSuggestionEnabled": false,
  "skipDangerousModePermissionPrompt": true
}
JSONEOF
        fi
    else
        echo -e "${BLUE}[DRY-RUN]${NC} cat > ~/.claude/settings.json (fallback 通用模板)"
    fi
    echo "  ✓ settings.json (fallback 通用模板)"
fi

# 17.6 MCP — 从 MCP_PROJECTS 扫描 mcp.json
MCP_MERGED=false
for proj in "${MCP_PROJECTS[@]}"; do
    [ -d "$proj" ] || { warn "MCP_PROJECTS 路径不存在: $proj"; continue; }
    MCP_JSON="$proj/mcp.json"
    if [ -f "$MCP_JSON" ] && [ "$DRY_RUN" != "1" ]; then
        python3 << MCPPY
import json, os
mcp_json = "$MCP_JSON"
settings = os.path.expanduser("~/.claude/settings.json")
with open(mcp_json) as f:
    mcp = json.load(f)
with open(settings) as f:
    cfg = json.load(f)
existing = cfg.get("mcpServers", {})
new_servers = mcp.get("mcpServers", {})
existing.update(new_servers)
cfg["mcpServers"] = existing
with open(settings, "w") as f:
    json.dump(cfg, f, indent=2)
print(f"  ✓ MCP merged from {os.path.basename('$proj')}")
MCPPY
        MCP_MERGED=true
    elif [ -f "$MCP_JSON" ] && [ "$DRY_RUN" = "1" ]; then
        echo -e "${BLUE}[DRY-RUN]${NC} 合并 MCP: $MCP_JSON"
        MCP_MERGED=true
    fi
done
if [ "$MCP_MERGED" != true ] && [ ${#MCP_PROJECTS[@]} -gt 0 ]; then
    echo -e "  ${YELLOW}⚠️  MCP_PROJECTS 已配置但未找到任何 mcp.json${NC}"
fi

# 17.7 settings.local.json
SETTINGS_LOCAL_SRC=""
for src in "$LATEST_BACKUP/settings.local.json" "$SAFE_ZONE/settings.local.json"; do
    [ -f "$src" ] && SETTINGS_LOCAL_SRC="$src" && break
done
if [ -n "$SETTINGS_LOCAL_SRC" ]; then
    dry cp "$SETTINGS_LOCAL_SRC" "$HOME/.claude/settings.local.json"
    echo "  ✓ settings.local.json"
fi

# P1: 恢复 .cc-switch/skills/（如果备份了）
if [ "$CC_SWITCH_EXISTS" = true ]; then
    CC_SWITCH_SRC=""
    for src in "$LATEST_BACKUP/cc-switch-skills" "$SAFE_ZONE/cc-switch-skills"; do
        [ -d "$src" ] && CC_SWITCH_SRC="$src" && break
    done
    if [ -n "$CC_SWITCH_SRC" ]; then
        if [ -d "$HOME/.cc-switch/skills" ] && [ "$(ls -A "$HOME/.cc-switch/skills" 2>/dev/null | wc -l | tr -d ' ')" -gt 0 ]; then
            echo -e "  ${YELLOW}⚠️ ~/.cc-switch/skills/ 已存在且非空，跳过覆盖${NC}"
        else
            dry mkdir -p "$HOME/.cc-switch/skills"
            [ "$(ls -A "$CC_SWITCH_SRC" 2>/dev/null | wc -l | tr -d ' ')" -gt 0 ] && dry cp -r "$CC_SWITCH_SRC/"* "$HOME/.cc-switch/skills/" 2>/dev/null || true
            echo "  ✓ .cc-switch/skills 已恢复"
        fi
    fi
fi

# P1: 恢复 .agents/skills/
if [ -d "$HOME/.agents" ] || [ -d "$LATEST_BACKUP/agents-skills" ]; then
    AGENTS_SRC=""
    for src in "$LATEST_BACKUP/agents-skills" "$SAFE_ZONE/agents-skills"; do
        [ -d "$src" ] && AGENTS_SRC="$src" && break
    done
    if [ -n "$AGENTS_SRC" ]; then
        if [ -d "$HOME/.agents/skills" ] && [ "$(ls -A "$HOME/.agents/skills" 2>/dev/null | wc -l | tr -d ' ')" -gt 0 ]; then
            echo -e "  ${YELLOW}⚠️ ~/.agents/skills/ 已存在且非空，跳过覆盖${NC}"
        else
            dry mkdir -p "$HOME/.agents/skills"
            [ "$(ls -A "$AGENTS_SRC" 2>/dev/null | wc -l | tr -d ' ')" -gt 0 ] && dry cp -r "$AGENTS_SRC/"* "$HOME/.agents/skills/" 2>/dev/null || true
            echo "  ✓ .agents/skills 已恢复"
        fi
    fi
fi

# P2: 恢复 RTK.md
RTK_SRC=""
for src in "$LATEST_BACKUP/RTK.md" "$SAFE_ZONE/RTK.md"; do
    [ -f "$src" ] && RTK_SRC="$src" && break
done
if [ -n "$RTK_SRC" ]; then
    dry cp "$RTK_SRC" "$HOME/.claude/RTK.md"
    echo "  ✓ RTK.md 已恢复"
fi

# ============================================================================
# 阶段 18: 最终验证
# ============================================================================
echo ""
echo "========================================"
echo "阶段 18: 最终验证"
echo "========================================"

PASS=0; FAIL=0
chk() { if eval "$1"; then echo -e "  ${GREEN}[✓]${NC} $2"; PASS=$((PASS+1)); else echo -e "  ${RED}[✗]${NC} $2"; FAIL=$((FAIL+1)); fi; }

chk "[ -f \"$HOME/.claude.json\" ]" "~/.claude.json 已生成"
chk "! security dump-keychain 2>/dev/null | grep -qi claude" "Keychain 无 Claude 残留"
chk "[ -d \"$HOME/.claude/hooks\" ] && ls \"$HOME/.claude/hooks/\"*.sh >/dev/null 2>&1" "Hooks 已恢复"
chk "[ -d \"$HOME/.claude/skills\" ] && [ \"\$(ls \"$HOME/.claude/skills/\" 2>/dev/null | wc -l | tr -d ' ')\" -gt 0 ]" "Skills 已恢复"
chk "grep -q statusLine \"$HOME/.claude/settings.json\" 2>/dev/null" "settings.json 含 statusLine"
chk "[ -f \"$HOME/.claude/CLAUDE.md\" ]" "CLAUDE.md 存在"
chk "! grep -q mms-bridge \"$HOME/.claude/settings.json\" 2>/dev/null" "settings.json 无旧 token"
chk "[ -d \"$HOME/.claude/plugins\" ] && [ \"\$(ls \"$HOME/.claude/plugins/\" 2>/dev/null | wc -l | tr -d ' ')\" -gt 0 ]" "Plugins 已恢复"
chk "[ -f \"$HOME/.claude/settings.local.json\" ]" "settings.local.json 存在"
if [ "$CC_SWITCH_EXISTS" = true ]; then
    chk "[ -d \"$HOME/.cc-switch/skills\" ]" ".cc-switch/skills 存在"
fi
if [ -d "$HOME/.agents" ]; then
    chk "[ -d \"$HOME/.agents/skills\" ]" ".agents/skills 已处理"
fi
# 遥测设置由用户自行决定，不强制检查
# chk "! grep -q DISABLE_NONESSENTIAL_TRAFFIC \"$HOME/.claude/settings.json\" 2>/dev/null" "未设置 DISABLE_NONESSENTIAL_TRAFFIC"
chk "[ ! -d \"$HOME/Library/Caches/com.anthropic.claudefordesktop\" ]" "Desktop 缓存已清除"

echo ""
echo "========================================"
echo -e "${GREEN}验证: $PASS 通过 / $FAIL 失败${NC}"
echo "========================================"

if [ "$FAIL" -gt 0 ]; then
    echo -e "${RED}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo -e "${RED}❌ 有 $FAIL 项验证未通过，脚本以非零状态退出${NC}"
    echo -e "${RED}   说明清理或恢复不完整，请检查上方 [✗] 项${NC}"
    echo -e "${RED}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    exit 1
fi

# ============================================================================
# Final Summary
# ============================================================================
echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo -e "${GREEN}✅ Claude 完全隔离 + 指纹重置 完成${NC}"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""
if [ ${#WARNINGS[@]} -gt 0 ]; then
    echo -e "${YELLOW}⚠️  本次运行遇到的 warnings（共 ${#WARNINGS[@]} 条）:${NC}"
    for w in "${WARNINGS[@]}"; do
        echo "   - $w"
    done
    echo ""
fi
echo "  配置文件:      $CONFIG_FILE"
echo "  SCAN_ROOTS:    ${#SCAN_ROOTS[@]} 个目录"
echo "  CLEAN_ROOTS:   ${#CLEAN_ROOTS[@]} 个目录"
echo "  MCP_PROJECTS:  ${#MCP_PROJECTS[@]} 个项目"
echo ""
echo "  如需调整配置，编辑 ~/.config/claudefxxk/config.sh"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""
echo "隔离完成。Claude 现在应该不认识这台电脑。"
echo ""
