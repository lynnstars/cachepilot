# CachePilot（暂定名）

**面向 AI 工程师/爱好者的 macOS 磁盘清理工具。**

> **状态：v0.3 alpha** — ad-hoc 签名内测版，尚未公证（暂无付费 Apple 开发者账号）。功能可用，但仍是早期版本。

痛点：装了 npm/pip/uv/Homebrew/conda/ollama/Docker 等一堆终端设施后，磁盘被**依赖包缓存和 AI 模型残留**占满——而传统清理工具（CleanMyMac 式"按 app 缓存分类"）清不干净、不懂依赖包语义、不敢动 conda/ollama/Docker。于是磁盘到 99% 时，"清理工具"反而帮不上忙。

CachePilot 专扫 AI 工程师会积累的东西，按工具分组展示 **大小 / 风险 / 为什么可删**，清理 = **移入废纸篓（可恢复）**，绝不硬删。

## 功能（v0.3）

- 🔍 按工具扫描依赖缓存与 AI 残留：
  | 类别 | 工具 |
  |---|---|
  | 包管理器 | npm、pnpm、yarn、pip、uv、Homebrew、cargo、go、gradle、conda pkg 缓存 |
  | AI 工具 | ollama 模型（仅展示）、HuggingFace hub 缓存、ComfyUI 临时文件 |
  | 浏览器自动化 | Playwright、camoufox 浏览器引擎 |
  | 构建产物 | Xcode DerivedData |
  | 应用缓存(白名单) | 剪映类剪辑软件素材缓存 |
- 🎯 每项标注：**大小、风险等级、为什么可删、对应的官方命令**
- 🗑️ 清理 = **移入废纸篓**（可恢复），不是永久删除
- 🚦 风险模型：🟢 低风险默认勾选 · 🟡 中风险手动勾 · 🔴 高/仅展示项（大模型、node_modules 清单等）**绝不提供一键删除**
- ⚙️ 规则库驱动：`rules/cleanable_rules.json` 定义一切——易审计、易扩展

## 为什么可信

1. **只清白名单缓存路径**——不碰文档、聊天记录、项目源码、模型文件（模型只展示不自动删）
2. **移废纸篓而非 rm**——清掉的东西都能从废纸篓恢复
3. **透明**——每项都写清"是什么、为什么可删、官方命令"
4. **无遥测、无网络请求**——纯本地扫描

## 安装（内测版）

1. 从 [Releases](../../releases) 下载 `CachePilot-v0.3-test.zip`
2. 解压，把 `CachePilot.app` 拖进「应用程序」
3. 首次打开：**右键 → 打开**（ad-hoc 签名未公证，Gatekeeper 会提示——属正常，等拿到 Developer ID 证书后消除）
   - 打不开就执行：`xattr -dr com.apple.quarantine /Applications/CachePilot.app`

## 使用

1. 点「扫描」——读规则库，实测本机各路径大小（只读）
2. 查看分组结果（类别 → 条目 → 大小 / 风险 / 原因 / 官方命令）
3. 勾选要清的项（🟢 默认已勾）
4. 点「移入废纸篓（可恢复）」→ 确认 → 完成，可用空间实时更新

## 开发

环境要求：macOS 14+，只需 Xcode **Command Line Tools**（不需要完整 Xcode——`swiftc` + 内置 SDK 即可编译 SwiftUI app）。

```bash
# 打包 .app
app/scripts/make-app.sh

# CLI 扫描器（同一套逻辑，Python）
python3 scanner/scan.py          # 只读预览
python3 scanner/scan.py --json   # 机器可读
```

```
app/                    # SwiftUI app 源码（无 Xcode 工程，swiftc 直编）
rules/cleanable_rules.json      # 规则库（唯一事实源）
scanner/scan.py                 # CLI 扫描器
prototype/                      # HTML 交互原型 & 清理清单
TEST_CASES.md                   # 测试案例
```

## 扩展规则库

在 `rules/cleanable_rules.json` 加一条：

```json
{
  "id": "my-tool-cache",
  "category": "package-manager",
  "tool": "my-tool",
  "name": "my-tool download cache",
  "risk": "low",
  "paths": ["~/.my-tool/cache"],
  "min_size_mb": 50,
  "why": "Cache of downloaded packages; re-downloaded on next use",
  "official_cmd": "my-tool cache clean",
  "default_clean": true
}
```

类别：`package-manager` · `ai-tools` · `browser-automation` · `build-artifacts` · `app-caches` · `general`

## 路线图

- [x] 规则库 v1 + 只读扫描器
- [x] SwiftUI app：扫描 → 分组 → 勾选 → 移废纸篓
- [x] ad-hoc 内测分发
- [ ] Developer ID 签名 + 公证（正式分发）
- [ ] GitHub Actions CI（打 tag 自动构建）
- [ ] 规则云更新（Pro）/ 定时扫描
- [ ] Mac App Store（沙盒受限版）评估

## 免责声明

本工具按规则库删除/移动文件。设计上偏保守（先进废纸篓、模型仅展示），但**清理前请务必检查扫描结果**——请对你自己机器的操作负责。内测版未签名/未公证，自行承担安装风险。

License：暂未选择，保留所有权利。
