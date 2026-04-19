#!/bin/bash
# ============================================================================
# claudefxxk proxy setup — idempotent marker-based install
# ============================================================================

set -e

MARKER_START="# >>> claudefxxk proxy"
MARKER_END="# <<< claudefxxk proxy"
ZSHRC="$HOME/.zshrc"

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

# Check if already installed
if [ -f "$ZSHRC" ] && grep -q "$MARKER_START" "$ZSHRC" 2>/dev/null; then
    echo -e "${YELLOW}⚠️  claudefxxk proxy 已安装 (marker 存在于 $ZSHRC)${NC}"
    echo "   如需重新安装，先手动删除 ~/.zshrc 中 $MARKER_START 到 $MARKER_END 之间的内容。"
    exit 0
fi

# Discover proxy port: test 31001 first, then 7897, then prompt
PROXY_PORT=""
for port in 31001 7897; do
    if curl -s --max-time 2 -x "http://127.0.0.1:$port" http://ip-api.com/json/ >/dev/null 2>&1; then
        PROXY_PORT="$port"
        break
    fi
done

if [ -z "$PROXY_PORT" ]; then
    echo "未检测到可用代理 (31001 / 7897)"
    read -p "请输入 HTTP 代理端口 [Enter=跳过]: " PROXY_PORT
    if [ -z "$PROXY_PORT" ]; then
        echo -e "${YELLOW}⊘ 跳过安装${NC}"
        exit 0
    fi
fi

echo -e "${GREEN}✓ 检测到可用代理端口: $PROXY_PORT${NC}"

# Build the function block
FUNCTION_BLOCK="
$MARKER_START
# claudefxxk proxy — auto-detects IP context for Claude CLI
# 安装: ./scripts/setup-proxy.sh
# 卸载: 删除 ~/.zshrc 中 $MARKER_START 到 $MARKER_END 之间的内容

_claude_pick_proxy() {
    for p in 31001 7897; do
        if curl -s --max-time 2 -x \"http://127.0.0.1:\$p\" http://ip-api.com/json/ >/dev/null 2>&1; then
            echo \"http://127.0.0.1:\$p\"
            return
        fi
    done
}

_claude_ip_context() {
    local proxy=\"\$1\"
    local raw
    raw=\$(curl -s --max-time 5 -x \"\$proxy\" http://ip-api.com/json/ 2>/dev/null)
    local timezone=\$(echo \"\$raw\" | python3 -c 'import sys,json; d=json.load(sys.stdin); print(d.get(\"timezone\",\"\"))' 2>/dev/null)
    local city=\$(echo \"\$raw\" | python3 -c 'import sys,json; d=json.load(sys.stdin); print(d.get(\"city\",\"\"))' 2>/dev/null)
    local region=\$(echo \"\$raw\" | python3 -c 'import sys,json; d=json.load(sys.stdin); print(d.get(\"regionName\",\"\"))' 2>/dev/null)
    local country=\$(echo \"\$raw\" | python3 -c 'import sys,json; d=json.load(sys.stdin); print(d.get(\"country\",\"\"))' 2>/dev/null)
    local ip=\$(echo \"\$raw\" | python3 -c 'import sys,json; d=json.load(sys.stdin); print(d.get(\"query\",\"\"))' 2>/dev/null)
    echo \"\$ip|\$timezone|\$city|\$region|\$country\"
}

_claude_load_snapshot() {
    local file=\"\$1\"
    [ -f \"\$file\" ] && cat \"\$file\" 2>/dev/null
}

_claude_save_snapshot() {
    local file=\"\$1\"
    shift
    printf '%s\\n' \"\$@\" > \"\$file\"
}

claude() {
    local proxy=\$(_claude_pick_proxy)
    if [ -z \"\$proxy\" ]; then
        echo '[claudefxxk] ⚠️  无可用代理，直连运行 Claude CLI'
        command claude \"\$@\"
        return
    fi

    local snapshot_file=\"\$HOME/.cache/claude-proxy-snapshot.env\"
    mkdir -p \"\$(dirname \"\$snapshot_file\")\"

    local ctx=\$(_claude_ip_context \"\$proxy\")
    local ip=\$(echo \"\$ctx\" | cut -d'|' -f1)
    local timezone=\$(echo \"\$ctx\" | cut -d'|' -f2)
    local city=\$(echo \"\$ctx\" | cut -d'|' -f3)
    local region=\$(echo \"\$ctx\" | cut -d'|' -f4)
    local country=\$(echo \"\$ctx\" | cut -d'|' -f5)

    [[ -z \"\${timezone}\" ]] && timezone=\"America/Los_Angeles\"

    local old=\$(_claude_load_snapshot \"\$snapshot_file\")
    local old_ip=\$(echo \"\$old\" | sed -n '1p')
    local old_tz=\$(echo \"\$old\" | sed -n '2p')

    if [ \"\$ip\" = \"\$old_ip\" ] && [ \"\$timezone\" = \"\$old_tz\" ]; then
        echo \"[Claude] IP: \${ip}\"
        echo \"[Claude] TZ: \${timezone}\"
        echo \"[Claude] localTime: \$(date \"+%m.%d %H:%M:%S\")\"
        echo \"[Claude] tzTime: \$(TZ=\"\${timezone}\" date \"+%m.%d %H:%M:%S\")\"
    else
        echo \"[Claude] IP: \${ip} (城市: \${city}, 地区: \${region}, 国家: \${country})\"
        echo \"[Claude] TZ: \${timezone}\"
        echo \"[Claude] localTime: \$(date \"+%m.%d %H:%M:%S\")\"
        echo \"[Claude] tzTime: \$(TZ=\"\${timezone}\" date \"+%m.%d %H:%M:%S\")\"
        echo \"[Claude] proxy: \${proxy}\"
        if [ -n \"\$old_ip\" ]; then
            echo \"[Claude] 变化: IP \${old_ip} → \${ip}, TZ \${old_tz} → \${timezone}\"
        fi
        _claude_save_snapshot \"\$snapshot_file\" \"\$ip\" \"\$timezone\" \"\$city\" \"\$region\" \"\$country\"
    fi

    HTTP_PROXY=\"\$proxy\" HTTPS_PROXY=\"\$proxy\" ALL_PROXY=\"\$proxy\" \
        TZ=\"\$timezone\" command claude \"\$@\"
}
$MARKER_END
"

# Append to .zshrc
echo "$FUNCTION_BLOCK" >> "$ZSHRC"
echo -e "${GREEN}✓ 已追加到 $ZSHRC${NC}"
echo ""
echo "生效方式:"
echo "  source ~/.zshrc"
echo ""
echo "卸载方式:"
echo "  删除 ~/.zshrc 中 '$MARKER_START' 到 '$MARKER_END' 之间的内容"
