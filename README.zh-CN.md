# CachePilot

**面向「装了一堆 AI/开发工具」的 macOS 磁盘瘦身工具。**

> **状态：v0.4.0 alpha** —— ad-hoc 签名的测试版，尚未公证（没有付费 Apple 开发者账号）。

磁盘被**依赖包缓存与模型残留**占满：npm/pip/uv/Homebrew/conda/Gradle，加上 ollama 模型、HuggingFace 下载、Docker 镜像、构建产物。CleanMyMac 式的工具不懂包管理器语义，也不敢动 conda/ollama/Docker，于是磁盘到 99% 时谁都帮不上忙。

CachePilot 扫两件事，合成**一份你可以按编号授权的清单**：

| | 扫什么 |
|---|---|
| **A · 缓存规则** | npm（`_cacache`、`_npx`）、pnpm store、Yarn、pip、uv、Homebrew、cargo、Go、Gradle、conda 包缓存、ollama 模型¹、HuggingFace、ComfyUI、insightface、Playwright、camoufox、Xcode DerivedData/DeviceSupport/Archives、Docker Desktop、微信¹、剪映 |
| **B · 大文件与冗余** | 超过阈值的大文件；**内容完全相同的重复文件**（SHA-256 校验，超大文件走首尾哈希快通道）；**疑似冗余版本**（`X-最新(1)`、`X-无字幕`、`report-v2-final` 按名称聚类） |

¹ 仅展示：让你知道空间去哪了，并给出正确的官方清理命令。

## 清理机制（两段式，请先读这段）

```
扫描 → 编号清单 → 你挑编号 → 暂存(stage) → 彻底释放(release)
                             │                │
                        移入废纸篓          永久删除
                        （完全可恢复）      （不可恢复，真正释放空间）
```

1. **stage 暂存**：把选中项移入废纸篓。可恢复（`cachepilot undo`），但**此时磁盘空间并没有释放**——CachePilot 会明确告诉你这一点（v0.3 在这里骗过用户）。
2. **release 彻底释放**：永久删除暂存项，真正回收空间。必须显式确认（CLI 要 `--confirm-irreversible`，GUI 是红色按钮）。
3. 每次暂存都会写**记录（manifest）**到 `~/Library/Application Support/CachePilot/manifests/`：原路径、废纸篓路径、大小、时间。`undo` 靠它工作，也让你任何时候都能查清「到底动了什么」。

不点名编号，什么都不会被删。先入废纸篓不是「额外保险」，而是「磁盘 90% 满时也敢移动 11GB」的唯一前提。

## 默认拒绝的路径

CachePilot 不扫描、也不允许操作：

- 系统路径（`/System`、`/Library`、`/Applications`、`/usr`、`/bin`、`/sbin`、`/etc`、`/var`、`/private`、`/Volumes`、`/opt`）
- 隐私目录（`~/.ssh`、`~/.gnupg`、`~/Library/Keychains`、`Messages`、`Safari`、`AddressBook`）
- **废纸篓本身**（v0.3 会把废纸篓移进废纸篓，必然失败；现在有护栏 + 回归测试）
- 符号链接、允许根目录之外的路径、不存在的路径
- 仅展示项（模型、Docker 映像、微信存储）

## 安装（测试版）

1. 从 [Releases](../../releases) 下载 `CachePilot-v0.4.0-test.zip`
2. 解压，把 `CachePilot.app` 拖进「应用程序」
3. 首次打开：**右键 → 打开**（ad-hoc 签名、未公证，Gatekeeper 会警告，属正常）
   - 仍被拦：`xattr -dr com.apple.quarantine /Applications/CachePilot.app`

## 命令行

```bash
bash app/scripts/build-cli.sh          # → app/build/bin/cachepilot

cachepilot plan                        # 编号报告：缓存规则 + 大文件 + 重复文件
cachepilot plan --mode cache --min-size 500MB --root ~/Downloads
cachepilot stage --select 1,3-5         # 把这几号移入废纸篓（可恢复）
cachepilot release --confirm-irreversible   # 彻底释放，真正腾出空间
cachepilot undo                        # 把上批暂存的还原
cachepilot manifests                   # 已暂存 / 已释放 / 已撤销
cachepilot doctor                      # 语言、路径、规则库、待释放体积
```

`--select` 的编号对应刚打印的那份清单（自动存到 `plans/latest.json`）。超过 60 分钟的清单会被拒绝，编号永远不会错位。

## 语言

界面**跟随系统语言**：`zh*` 一律中文；**其他任何语言一律英文**。可用 `--lang zh|en`（CLI）、`CACHEPILOT_LANG`（两者）或界面右上角的地球菜单覆盖。规则库里的文案本身就是双语的（`{"en": …, "zh": …}`）。

## 规则库

`rules/cleanable_rules.json`（schema v2）是唯一事实来源：双语文案、风险等级、路径、`min_size_mb`、为什么可删、官方命令、`default_clean` / `show_only`。

加载顺序：App bundle → `CACHEPILOT_RULES` → 可执行文件同级 → `~/Library/Application Support/CachePilot/rules/`（不改代码热更新规则）→ 开发时的仓库 `rules/`。

## 开发

要求：macOS 14+，只需 Xcode **Command Line Tools**（不需要完整 Xcode，`swiftc` + SDK 就能编译 SwiftUI app）。

```bash
bash app/scripts/make-app.sh      # 打包 CachePilot.app（ad-hoc 签名，Info.plist 一起 sealed）
bash app/scripts/build-cli.sh     # 编译 cachepilot CLI（同一内核）
bash scripts/run-tests.sh         # Swift 单测 + CLI 端到端 + Python 测试
```

Swift 内核是唯一引擎：App 与 CLI 调用完全相同的代码，所以 CI 里测的就是你实际在跑的。

## 路线图（还没做，不吹）

- [ ] Developer ID 签名 + 公证（正式分发）
- [ ] App 图标
- [ ] node_modules / venv 清单（目录级扫描；目前只列大文件）
- [ ] Docker prune 集成（调用 `docker system prune` + 收缩磁盘映像）——目前仅展示
- [ ] 规则云更新（Pro）/ 定时后台扫描
- [ ] Mac App Store 可行性评估（沙箱限制任意缓存访问）

## 许可

尚未选定 —— 保留所有权利。
