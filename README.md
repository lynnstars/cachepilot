# AI Disk Cleaner（暂定名：CachePilot）

面向 AI 工程师/爱好者的 macOS 磁盘清理工具。
痛点：装了 npm/pip/uv/Homebrew/conda/ollama/Docker 等一堆终端设施后，
传统清理工具（按 app 缓存分类）清不干净、不懂依赖包语义、不敢动 AI 模型残留。

## 设计原则
1. **只清缓存，不碰数据**：白名单路径 + 风险分级（绿=随便清 / 黄=看清楚再清 / 红=只展示不自动删）
2. **删除 = 移入废纸篓**：所有清理可恢复（对应 macOS 的 trashItem）
3. **透明**：每一项标注"为什么可删、删了会怎样、对应官方命令"
4. **规则库驱动**：rules/*.json 定义清理对象，未来可云更新（Pro）

## 路线
- Step1（当前）：规则库 v1 + CLI 扫描器，真机验证（只扫描预览，不删除）
- Step2：确认分组/文案 → 测试案例
- Step3：SwiftUI app（扫描→分组→勾选→移废纸篓）
- Step4：Developer ID 签名 + notarization 分发（MVP 不上 MAS，沙盒会阉割功能）
- Step5：内测迭代
- Step6：Pro 功能（规则云更新/定时扫描）+ MAS 受限版决策

## 目录结构
```
rules/cleanable_rules.json   # 规则库 v1
scanner/scan.py              # CLI 扫描器（只读预览）
README.md
```
