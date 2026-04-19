# Review Notes

## 设计决策

### CLEAN_ROOTS 默认为空

**问题**: 个人版脚本硬编码了 10+ 个项目目录，开源版不能假设用户的目录结构。

**决策**: `CLEAN_ROOTS` 默认为空数组 `()`。未配置时 phase 10 明确提示用户如何配置，不做任何 `$HOME` fallback 扫描。

### 零静默跳过原则

**问题**: 如果 MMS/cc-switch/.agents 不存在，脚本应该怎么做？

**决策**: 所有 opt-in 功能在未配置/不存在时：
1. 输出 soft warning（黄色 ⚠️）
2. 计入 `WARNINGS` 数组
3. 在 Final Summary 中统一列出

绝不静默跳过，让用户清楚知道哪些功能没有生效。

### 配置分离

**问题**: 个人版脚本中路径、项目名、工具名全部硬编码。

**决策**: 拆分为三类配置：
- `SCAN_ROOTS`: 用于 git dirty 检查
- `CLEAN_ROOTS`: 用于项目级 `.claude` 清理
- `MCP_PROJECTS`: 用于 MCP server 扫描

各自独立，互不依赖。

### Hooks 恢复策略

**问题**: 个人版依赖 Codex backfill 的 repo-hooks 目录结构。

**决策**: 开源版 hooks 恢复只从 backup/safe_zone 读取。如果用户没有备份 hooks，脚本提示运行 `backup-missing-to-safe-zone.sh` 先备份。`statusLine.command` 由内置 `templates/settings.json` 兜底，不依赖外部 hooks 文件。

### Proxy 协议

**问题**: Claude CLI 的 Node.js HTTP 客户端不支持 socks5。

**决策**: 统一使用 `http://` 代理。`setup-proxy.sh` 自动探测 31001→7897 端口，使用 ip-api.com 查询 IP/TZ 上下文。

### setup-proxy.sh 安装方式

**问题**: `cat >> ~/.zshrc` 追加方式不可重复、不可卸载。

**决策**: 使用 marker-based 安装（`# >>> claudefxxk proxy` / `# <<< claudefxxk proxy`），idempotent：已安装时检测到 marker 直接退出。

## 已知限制

1. **macOS only**: 进程管理、路径、Keychain 操作均针对 macOS 设计
2. **bash 3.2**: 兼容 macOS 默认 bash，不使用 bash 4+ 特性
3. **HTTP proxy only**: Claude CLI 不支持 socks5
4. **Hooks 无内置兜底**: 如果用户未备份 hooks，恢复后无 hooks（settings.json 模板提供基础 statusLine）

## 版本历史

| 版本 | 日期 | 变更 |
|------|------|------|
| v3 | 2026-04 | 开源版首次发布 |
