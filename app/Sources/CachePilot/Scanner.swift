import Foundation

// MARK: - 兼容壳（v0.3 → v0.4）
//
// v0.3 的规则扫描器（`enum Scanner`、`ScanItem`、`ScanItem.trash(paths:)`）在 v0.4 拆成：
//   · `RuleScanner`（Finder.swift）—— 规则库扫描，只读，实占口径，带超时与取消
//   · `BigFinder`（Finder.swift）—— 大文件 / 重复内容 / 冗余版本
//   · `Actions`（Actions.swift）—— 暂存（移入废纸篓）/ 彻底释放 / 撤销 + 安全护栏
//
// 拆分的直接原因：v0.3 的 `Scanner.trash()` 允许把「废纸篓自己」移进废纸篓
// （目标路径落在源路径内部 → 必然失败），且清理后不释放空间。新内核
// 在 `SafetyConfig.validate()` 里把这类路径硬拦住（见 refuseTrashItself）。
//
// 本文件保留占位，避免历史引用断链；不在其中定义任何符号。
