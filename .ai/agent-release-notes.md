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

---

## 2026-04-19 11:15+08:00 | Claude

**Commit:** `53a768f` on `main`

**改动文件范围:**
- `scripts/claude-nuke-and-restore.sh`
- `scripts/backup-missing-to-safe-zone.sh`
- `scripts/setup-proxy.sh`

**改动内容摘要:**
Bugfix 轮：修复 2 个 runtime bug + 1 non-blocking + mode change。

- **P0 fix**: SAFE_ZONE / CODEX_BF 改为 `\`: \${VAR:=default}\``，用户 config.sh 自定义值不再被硬编码覆盖
- **P1 fix**: backup 脚本 hooks 输出目录从 `safe-zone-hooks/` 改为 `hooks/`，与恢复脚本的读取路径一致
- **non-blocking**: SCAN_ROOTS=() 时添加 soft warning + 配置提示（两个脚本）
- **setup-proxy.sh**: commit mode change (+x)

**Release Note Bullets:**
- fix: respect custom SAFE_ZONE / CODEX_BF from config.sh
- fix: unify hooks backup/restore path (hooks/)
- fix: add SCAN_ROOTS=() soft warning instead of silent skip

**验证结果:**
- `bash -n` 三个脚本全部通过 ✅
- GitHub push `53a768f` ✅

---

## 2026-04-19 11:20+08:00 | 用户复核 — 放行确认

**结论**: 开源版 `48b2855` 通过复核，无 blocking findings，可对外按"已完成"推进。

**确认项:**
- P0 已确认修复：`: ${VAR:=...}` 不再覆盖 config.sh 自定义值
- P1 已确认修复：hooks 备份/恢复路径一致 (`hooks/`)
- non-blocking 已确认修复：SCAN_ROOTS=() 时明确 warning
- 工作树干净，无未提交逻辑改动

**遗留非 blocking 提醒:**
1. setup-proxy.sh 是"已安装就退出"型 idempotent，非"原地更新型"，后续升级 proxy block 时需注意
2. 个人版 (`../claudefxxk/`) EXECUTE.md / v3/最终方案.md 仍有旧的 LA / socks5 / `cat >> ~/.zshrc` 叙述，建议后续单独清理
