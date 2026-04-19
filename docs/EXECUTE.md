# 执行手册

## 完整流程（首次使用）

### 1. 克隆仓库

```bash
git clone git@github.com:CtriXin/claudefxxk.git
cd claudefxxk
```

### 2. 创建配置文件

```bash
mkdir -p ~/.config/claudefxxk
cat > ~/.config/claudefxxk/config.sh << 'EOF'
SCAN_ROOTS=(
    "$HOME/your-project-a"
    "$HOME/your-project-b"
)

CLEAN_ROOTS=(
    "$HOME/your-project-a"
    "$HOME/your-project-b"
)

MCP_PROJECTS=(
    "$HOME/your-project-a"
)
EOF
```

### 3. 备份资产

```bash
./scripts/backup-missing-to-safe-zone.sh
```

检查输出目录 `~/claude_safe_zone/backup-run-*/`，确认包含：
- `skills-entity/` — 实体 skill 文件
- `skills.symlink-map.txt` — symlink 映射
- `plugins/` — 插件
- `hooks/` — hooks
- `CLAUDE.md` — 系统提示
- `settings-current-session-sanitized.json` — 脱敏后的 settings
- `settings.local.json` — 本地设置

### 4. 执行清理 + 重装 + 恢复

```bash
./scripts/claude-nuke-and-restore.sh
```

按提示逐步确认各阶段。关键决策点：
- **Phase 0**: 确认 API key 已处理、repo 已 push
- **Phase 1**: 确认 MMS 工作已保存（如果运行中）
- **Phase 8**: 先轻清当前活跃 Chrome profile 的 `Local Storage / Session Storage`，然后在你确认已安全关闭 Chrome 后，再决定是否深度删除 `IndexedDB / Cookie DB`
- **Phase 15**: 可选择 npm 重新安装或跳过
- **Phase 16**: 首次启动后自动对比新旧 userID

### 5. 安装代理（可选）

```bash
./scripts/setup-proxy.sh
source ~/.zshrc
```

### 6. 验证

```bash
claude --version
# 确认是全新安装的版本
```

---

## DRY-RUN 模式

在正式执行前，建议先 dry-run：

```bash
DRY_RUN=1 ./scripts/claude-nuke-and-restore.sh
```

所有 destructive 命令只会打印，不会实际执行。

---

## 常见问题

### Q: CLEAN_ROOTS 未配置会怎样？
A: Phase 10 会显示 warning 并跳过，不会扫描任何目录。Final Summary 中会列出所有 warnings。

### Q: 我没有 MMS/cc-switch/.agents，需要配置吗？
A: 不需要。脚本会自动检测这些工具是否存在，不存在时跳过相关步骤并给出 soft warning。

### Q: 备份脚本的 settings.json 脱敏是什么？
A: 备份时自动剔除 `env` 和 `attribution` 字段（通常包含 token 和身份指纹），确保备份文件可以安全地在新身份下恢复。

### Q: 我可以多次运行吗？
A: 可以。脚本设计为幂等：每次运行都会生成新的备份目录，恢复时优先使用最新备份。

### Q: 如何卸载 proxy？
A: 编辑 `~/.zshrc`，删除 `# >>> claudefxxk proxy` 到 `# <<< claudefxxk proxy` 之间的所有内容，然后 `source ~/.zshrc`。
