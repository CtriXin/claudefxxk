# Agent Release Notes — claudefxxk-open-source

---

## 2026-04-19 11:00+08:00 | Claude

**Commit:** `406886f` on `main`

**改动文件范围:**
- `scripts/claude-nuke-and-restore.sh` (18 阶段清理+重装+恢复)
- `scripts/backup-missing-to-safe-zone.sh` (资产备份+脱敏)
- `scripts/setup-proxy.sh` (idempotent proxy 安装)
- `templates/settings.json` (内置通用模板)
- `templates/mcp.json` (空 MCP 模板)
- `README.md`
- `docs/EXECUTE.md`
- `docs/review-notes.md`
- `LICENSE` (MIT)
- `.gitignore`

**改动内容摘要:**
开源版首次发布。基于个人版 v3 通用化：
1. 配置化：SCAN_ROOTS / CLEAN_ROOTS / MCP_PROJECTS 拆分为独立数组，通过 `~/.config/claudefxxk/config.sh` 读取
2. CLEAN_ROOTS 默认为空 `()`，不扫 `$HOME`，未配置时 soft warning + final summary
3. MMS/cc-switch/.agents 检测改为条件执行，不存在时不静默跳过
4. repo-mcp 扫描改为 MCP_PROJECTS 配置驱动
5. settings.json fallback 改为内置通用模板（无硬编码路径）
6. .zshrc 清理改为删除 claudefxxk proxy marker 块
7. setup-proxy.sh 使用 idempotent marker-based 安装

**Release Note Bullets:**
- feat: open-source v3 — configurable cleanup + restore toolkit for Claude CLI
- feat: SCAN_ROOTS / CLEAN_ROOTS / MCP_PROJECTS config split
- feat: idempotent setup-proxy.sh with marker-based install
- feat: built-in templates/settings.json fallback (no hardcoded paths)
- fix: zero-silent-skip — all opt-in features emit soft warnings
- docs: README + EXECUTE.md + review-notes.md

**验证结果:**
- `bash -n claude-nuke-and-restore.sh` ✅
- `bash -n backup-missing-to-safe-zone.sh` ✅
- `bash -n setup-proxy.sh` ✅
- 无硬编码个人路径（grep 验证）✅
- GitHub push `master → main` forced update ✅
- 脚本权限 `+x` ✅
