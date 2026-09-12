# CachePilot 测试说明（v0.4）

安全承诺（可被测试证明）：**任何清理都必须先经过「暂存 → 用户确认编号」；暂存=移入废纸篓可恢复；只有显式 release 才真正释放空间；受保护路径/符号链接/废纸篓自身一律拒绝。**

## 一、自动化测试（每次提交/发版都跑）

```bash
bash scripts/run-tests.sh
```

| 层 | 覆盖 | 当前结果 |
|---|---|---|
| Swift 单元测试（`app/Tests/run-tests.swift`） | 语言解析、文案表完整性、规则库 schema v2 与数据回归、安全护栏、重复/冗余检测、暂存-撤销-释放、清单编号与过期保护、双语报告渲染 | 106 项断言 |
| CLI 端到端（`scripts/run-tests.sh` 内） | plan → stage → release / undo、dry-run、护栏拒绝、系统语言切换（ja/de → 英文；zh-Hans/zh-Hant → 中文） | 35 项断言 |
| Python 预览脚本（`tests/test_scan_py.py`） | 只读保证、schema v2 解析、双语输出、`--trash` 拒绝执行 | 6 个用例 |

关键回归用例（对应 v0.3 的真实缺陷）：

- `no rule points at ~/.Trash` —— v0.3 会把废纸篓移进废纸篓（目标在源内部，必然失败）
- `pnpm rule points at the real macOS store` —— v0.3 写的路径在 macOS 上不存在，漏检 803MB
- `npm rule covers _npx` —— v0.3 漏掉 npm 最大的那块缓存
- `release without --confirm-irreversible refused` —— 彻底释放必须显式确认
- `release ignores items not staged by us` —— 只删自己暂存进废纸篓的东西
- `refuseTrashItself / protected / symlink / outside roots` —— 四类路径硬拦
- 语言：`ja-JP → en`、`de-DE → en`、`zh-Hant-TW → zh`（其他语言默认英文）

## 二、手工验收（自动化测不到的部分）

| # | 步骤 | 预期 |
|---|---|---|
| M1 | 双击 `CachePilot.app`（未做 notarize） | Gatekeeper 拦截 → 右键「打开」可进；这是预期行为 |
| M2 | 界面语言 | 系统为中文 → 中文；把系统语言改成日文再启动 → 英文；右上角地球菜单可手动覆盖 |
| M3 | 点「扫描」 | 进度文本实时更新，可点「取消扫描」中断；结果分三页（缓存规则 / 大文件 / 重复与冗余） |
| M4 | 大文件页 | 默认**不勾选**任何项；每行显示编号、体积、年龄、真实路径 |
| M5 | 勾选若干 → 移入废纸篓 | 顶部出现橙色横幅「已暂存…空间尚未释放」，且「当前可用」数字**不变**（这是设计，不是 bug） |
| M6 | 点「彻底释放空间」 | 红色确认弹窗；确认后「当前可用」数字**变大**，横幅变成「已彻底释放 X 项 · 释放 Y（实测）」 |
| M7 | 暂存后点「撤销并还原」 | 文件回到原路径；用 `cachepilot manifests` 可看到 `undone` |
| M8 | 废纸篓检查 | 暂存项名为 `原名-CachePilot-<批次号>`，可直接从 Finder 拖回原处 |
| M9 | 无「完全磁盘访问」权限时 | 扫描不崩；读不到的目录按「不存在/0」处理并继续 |
| M10 | 磁盘接近满（<2GB）时扫描 | 仍能完成（du 有 90s 超时保护），超阈值时 `plan` 会提示 truncated |

## 三、发布前检查清单

- [ ] `bash scripts/run-tests.sh` 全绿
- [ ] `bash app/scripts/make-app.sh` 成功，且 `codesign -dv` 显示 `Info.plist` 已 sealed（不再有 `not bound`）
- [ ] Release 里的 zip 与本地 `app/build/CachePilot.app` 内容一致（`shasum -a 256` 比对二进制）
- [ ] `Info.plist` 版本号 = 发布 tag（`0.4.0`）
- [ ] 规则库 `schema_version` 为 2，每条规则都有 `en` + `zh` 文案
- [ ] README 里承诺的功能，逐条 grep 规则库/代码确认存在（v0.3 曾宣称支持 conda/Docker/node_modules 而规则库为空）
