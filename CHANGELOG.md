# Changelog

## 0.4.0 — 2026-09-13

### Breaking changes（行为变了，请注意）

- **清理改为两段式**：`stage`（移入废纸篓，可恢复，**不释放空间**）→ `release --confirm-irreversible`（永久删除，真正释放空间）。
  v0.3 只有第一段，且从不告知用户空间没被释放。
- **按编号授权**：所有入口（CLI / GUI）都输出编号清单，用户显式点编号或 `--select 1,3-5`；清单落盘 `plans/latest.json`，超过 60 分钟拒绝执行，编号不会错位。
- **`scanner/scan.py --trash` 不再执行清理**（退出码 2）：清理动作只有带记录与撤销的 Swift 内核能做。
- **规则库 schema v2**：所有面向用户的文案改为 `{"en": …, "zh": …}` 双语对象（英文必填，中文缺失回退英文）。
- **语言跟随系统**：`zh*` → 中文；**其他任何语言 → 英文**；`--lang` / `CACHEPILOT_LANG` 可覆盖。

### Fixed

- **废纸篓自身不再被当作可清理项**：v0.3 的 `trash` 规则会把 `~/.Trash` 移进 `~/.Trash`（目标在源内部，必然失败）。现在规则已移除，且 `SafetyConfig.validate()` 对「废纸篓本身/其祖先」硬拦，并有沙箱回归测试。
- **pnpm 规则路径修正**：macOS 真实位置是 `~/Library/pnpm/store`（v0.3 写的两个路径都不存在，漏检约 803MB）；风险等级改为 `medium`（与「项目还在用 pnpm 时别整体清」的说明一致）。
- **npm 规则补 `_npx`**：通常比 `_cacache` 更大的一块此前完全没覆盖。
- **补齐 README 曾宣称但没有的规则**：conda 包缓存（多发行版路径）、Docker Desktop（仅展示 + `docker system prune` 指引）、微信存储（仅展示 + 微信内清理路径）。
- **Xcode 覆盖扩展**：新增 iOS/watchOS DeviceSupport、Archives（Archives 标 `medium` 且默认不勾，因为删了无法重新下载）。
- **发布包可复现**：`make-app.sh` 现在显式 `codesign --force --deep --sign - --identifier com.cachepilot.app`，Info.plist 被 sealed；版本号由脚本注入（不再出现 Info.plist 0.1.0 / Release v0.3 的不一致）。
- **测试**：新增 106 项 Swift 单测 + 35 项 CLI 端到端断言 + 6 个 Python 用例，覆盖语言、规则数据、安全护栏、重复/冗余检测、暂存-撤销-释放全链路；CI 每次提交都跑。

### Added

- **B 类检测（新增）**：大文件（体积阈值 + 类型 + 年龄）、内容重复（SHA-256 校验；超大文件走首尾哈希并标注 `likely`）、疑似冗余版本（名称归一化聚类：`(1)`、`副本`、`最新`、`最终`、`v2`、`无字幕`、`横/竖版`、日期等）。
- **记录与撤销**：每次暂存写 manifest（原路径/废纸篓路径/大小/时间），`cachepilot undo` 一键还原，`cachepilot manifests` 查历史。
- **安全护栏**：允许根目录、受保护路径、隐私目录（`~/.ssh` 等）、符号链接、CachePilot 自身数据目录、仅展示项全部拒绝；只有 CachePilot 暂存进废纸篓的东西才允许被 release。
- **扫描健壮性**：`du` 90s 超时保护、并行 4 路扫描、支持取消、大文件遍历有 `--max-seconds` 预算并标注 truncated。
- **同一内核双前端**：`cachepilot` CLI 与 GUI 共用 `Sources/CachePilot/` 内核（v0.3 的 Swift 与 Python 两套实现互相漂移，已收敛）。
- **规则热更新**：规则库可从 `CACHEPILOT_RULES` 或 `~/Library/Application Support/CachePilot/rules/` 加载，不必发版。
- **CI**：push/PR 跑测试；打 tag 自动构建 `.app`、打包 zip 并上传到对应 Release。

## 0.3.0 — 2026-09-09

- 首个测试版本：规则库 + SwiftUI app（扫描 → 勾选 → 移入废纸篓）+ CLI 扫描器 + HTML 原型。
- 已知问题（本版修复）：清理不释放空间且未告知；废纸篓规则必然失败；pnpm 路径错误；npm 漏 `_npx`；README 宣称的 conda/Docker/node_modules 无对应规则；发布二进制与源码不一致；签名不含 Info.plist。
