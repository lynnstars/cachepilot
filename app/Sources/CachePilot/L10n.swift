import Foundation

// MARK: - 语言解析与文案表
// 规则：取系统首选语言；以 zh 开头 → 中文；其余（含 en 与其他所有语言）→ 英文。
// 可用 CACHEPILOT_LANG / --lang 覆盖（测试与 CI 用）。

public enum Lang: String, Codable, CaseIterable {
    case en
    case zh

    /// 语言显示名（用于 --lang 帮助与 doctor 输出）
    public var displayName: String {
        switch self {
        case .en: return "English"
        case .zh: return "中文"
        }
    }
}

public enum L10n {

    /// 当前进程语言（由系统语言/环境变量决定）。测试里可临时赋值后复位。
    public static var current: Lang = resolve()

    /// 判定规则：env 覆盖 > 系统首选语言顺序里的第一个受支持语言 > 英文。
    /// 显式给了不支持的语言（如 CACHEPILOT_LANG=fr）也按「其他语言 → 英文」处理。
    public static func resolve(preferred: [String] = Locale.preferredLanguages,
                               env: String? = ProcessInfo.processInfo.environment["CACHEPILOT_LANG"]) -> Lang {
        if let raw = env?.trimmingCharacters(in: .whitespacesAndNewlines), !raw.isEmpty {
            let l = raw.lowercased()
            if l.hasPrefix("zh") { return .zh }
            return .en
        }
        for p in preferred where !p.isEmpty {
            let l = p.lowercased()
            if l.hasPrefix("zh") { return .zh }
            if l.hasPrefix("en") { return .en }
        }
        return .en   // 其他任何语言 → 默认英文
    }

    // MARK: 文案键（rawValue = 英文原文，缺失翻译时回退英文）

    public enum Key: String, CaseIterable {
        // 通用
        case appTagline = "Disk reclaimer for AI/dev machines"
        case riskLow = "low risk"
        case riskMedium = "medium risk"
        case riskHigh = "high risk"
        case riskShowOnly = "display only"
        case yes = "yes"
        case no = "no"
        case none = "none"
        case unknown = "unknown"
        case days = "%d days"
        case recovered = "recoverable"
        case irreversible = "irreversible"

        // 报告
        case reportTitle = "CachePilot %@ — scan report"
        case diskLine = "Disk: %@ used / %@ free (%@ in use)"
        case scannedSummary = "%d items · %@ selectable · %@ display-only"
        case sectionCache = "Cache & dependency rules"
        case sectionBig = "Large files (by size)"
        case sectionDuplicates = "Duplicate files (identical content)"
        case sectionVersions = "Redundant versions (similar names)"
        case itemWhy = "why: %@"
        case itemOfficialCmd = "official command: %@"
        case itemOfficialCmdNone = "official command: (none — manual)"
        case itemSize = "size: %@"
        case itemAge = "age: %@"
        case itemPath = "path: %@"
        case itemKeepHint = "keep: %@"
        case itemPaths = "paths: %@"
        case groupCount = "%d files"
        case showOnlyNote = "display only — CachePilot will not touch it"
        case planHint = "Numbers are stable for this plan. Authorize with --select 1,3-5"
        case noItems = "Nothing found above the current thresholds."
        case planSavedTo = "plan saved: %@"
        case totalSelectable = "authorizable now: %@"
        case totalShowOnly = "display-only total: %@"

        // 执行
        case staging = "Moving %d items to the Trash…"
        case stagedResult = "Staged %d items (%@) to the Trash. NO space freed yet — they are still recoverable."
        case stagedFailed = "%d item(s) failed to stage"
        case stagedFailedList = "failed: %@"
        case releaseExplain = "To actually free disk space, release the staged items (irreversible)."
        case releasing = "Releasing %d staged items permanently…"
        case releasedResult = "Released %d items, freed %@ (measured by disk delta)."
        case nothingStaged = "Nothing staged for this plan."
        case undoResult = "Undo: restored %d item(s) to their original paths."
        case undoFailed = "%d item(s) could not be restored"
        case undoNothing = "No staged manifest to undo."
        case manifestList = "Staged manifests:"
        case manifestLine = "%@ · %@ · %d items · %@ · %@"
        case manifestStateStaged = "staged (recoverable)"
        case manifestStateReleased = "released (gone)"
        case manifestStateUndone = "undone"
        case dryRunNote = "[dry run] no file was moved."
        case confirmRequired = "Permanent release requires --confirm-irreversible."

        // 安全护栏
        case refuseOutsideRoots = "Refused: %@ is outside the allowed roots (%@)"
        case refuseProtected = "Refused: %@ is a protected path"
        case refuseSymlink = "Refused: %@ is a symlink"
        case refuseNotRegular = "Refused: %@ is not a regular file"
        case refuseTrashItself = "Refused: %@ is the Trash folder (or contains it) — CachePilot never moves the Trash into itself"
        case refuseShowOnly = "Refused: %@ is display-only and cannot be cleaned"
        case refuseNotFound = "Refused: %@ does not exist"
        case refuseNotStaged = "Refused: %@ was not staged by CachePilot"
        case refuseTargetExists = "Skipped: %@ already exists, not overwriting"

        // 分类（缓存规则类别）
        case catPackageManager = "Package manager caches"
        case catAITools = "AI tool residue"
        case catBrowserAutomation = "Browser automation"
        case catBuildArtifacts = "Build artifacts"
        case catAppCaches = "App caches (whitelisted)"
        case catGeneral = "General"

        // 大文件种类
        case kindVideo = "video"
        case kindArchive = "archive"
        case kindInstaller = "installer / disk image"
        case kindModel = "AI model file"
        case kindDocument = "document"
        case kindData = "data"
        case kindOther = "other"
        case bigFilesNote = "Large files are never pre-selected. Pick the numbers you approve."

        // 重复/冗余
        case dupExact = "identical content (verified by hash)"
        case dupLikely = "almost certainly identical (size + head/tail hash)"
        case versionSuspect = "similar names — likely redundant versions; verify before deleting"
        case keepOldest = "oldest copy"
        case keepNewest = "newest copy"

        // CLI / doctor
        case usage = """
        CachePilot — disk reclaimer for AI/dev machines (cache rules · large files · duplicates)

        USAGE:
          cachepilot plan    [--mode cache|big|dup|all] [--min-size 200MB] [--root PATH]... [--json] [--lang en|zh]
          cachepilot stage   --select 1,3-5 [--dry-run] [--lang en|zh]
          cachepilot release --confirm-irreversible [--manifest ID] [--lang en|zh]
          cachepilot undo    [--manifest ID] [--lang en|zh]
          cachepilot manifests
          cachepilot doctor

        SAFETY: everything stages to the Trash first (recoverable). Space is only freed
        when you explicitly run `release`, which is irreversible. Paths outside the
        allowed roots, protected paths, symlinks and display-only items are refused.
        """
        case doctorEnv = "language: %@ (from %@)"
        case doctorHome = "home: %@"
        case doctorTrash = "trash dir: %@"
        case doctorManifest = "manifest dir: %@"
        case doctorRules = "rule library: %d rules, schema v%d"
        case doctorRoots = "allowed roots: %@"
        case doctorPlan = "latest plan: %@"

        // GUI
        case uiScan = "Scan"
        case uiRescan = "Rescan"
        case uiScanning = "Scanning… (%@)"
        case uiCancel = "Cancel"
        case uiCancelled = "Cancelled"
        case uiReady = "Ready"
        case uiSelectRecommended = "Select recommended"
        case uiClearSelection = "Clear selection"
        case uiStage = "Move to Trash (recoverable)"
        case uiStageTitle = "Confirm staging"
        case uiStageMessage = "Move %d items (%@) to the Trash? They stay recoverable — space is not freed yet."
        case uiRelease = "Release permanently"
        case uiReleaseTitle = "Permanently delete staged items?"
        case uiReleaseMessage = "This deletes %d staged items (%@) for good. They cannot be restored from the Trash afterwards."
        case uiUndo = "Undo (restore)"
        case uiStagedBanner = "%@ staged in the Trash and still recoverable — disk space has not been freed yet."
        case uiFreedBanner = "Released %d items · freed %@ (measured)."
        case uiFreeNow = "free now"
        case uiTabCache = "Cache rules"
        case uiTabBig = "Large files"
        case uiTabDup = "Duplicates & versions"
        case uiMinSize = "Min size"
        case uiEmptyState = "Press Scan to see what is reclaimable on this machine."
        case uiRuleHint = "Green rows are pre-selected. Red rows are display-only."
        case uiBigHint = "Nothing is pre-selected here — check only what you are sure about."
        case uiNotSelectable = "not selectable"
        case uiFilterAll = "All"
        case uiResultTitle = "Result"
        case uiOK = "OK"
        case uiSelectByNumber = "Authorize by number"
    }

    // MARK: 中文表（缺项自动回退英文；测试会断言无缺项）

    private static let zh: [Key: String] = [
        .appTagline: "面向 AI/开发者的磁盘瘦身工具",
        .riskLow: "低风险",
        .riskMedium: "中风险",
        .riskHigh: "高风险",
        .riskShowOnly: "仅展示",
        .yes: "是",
        .no: "否",
        .none: "无",
        .unknown: "未知",
        .days: "%d 天",
        .recovered: "可恢复",
        .irreversible: "不可恢复",

        .reportTitle: "CachePilot %@ — 扫描报告",
        .diskLine: "磁盘：已用 %@ / 可用 %@（占用 %@）",
        .scannedSummary: "%d 项 · 可授权 %@ · 仅展示 %@",
        .sectionCache: "缓存与依赖规则",
        .sectionBig: "大文件",
        .sectionDuplicates: "重复文件（内容一致）",
        .sectionVersions: "冗余版本（名称相近）",
        .itemWhy: "为什么可清：%@",
        .itemOfficialCmd: "官方命令：%@",
        .itemOfficialCmdNone: "官方命令：（无，需手动处理）",
        .itemSize: "大小：%@",
        .itemAge: "最近修改：%@",
        .itemPath: "路径：%@",
        .itemKeepHint: "建议保留：%@",
        .itemPaths: "路径：%@",
        .groupCount: "%d 个文件",
        .showOnlyNote: "仅展示，CachePilot 不会动它",
        .planHint: "编号在本次清单内固定。用 --select 1,3-5 授权",
        .noItems: "当前阈值下没有扫描到可清理项。",
        .planSavedTo: "清单已保存：%@",
        .totalSelectable: "本次可授权：%@",
        .totalShowOnly: "仅展示合计：%@",

        .staging: "正在把 %d 项移入废纸篓…",
        .stagedResult: "已把 %d 项（%@）暂存到废纸篓。**空间尚未释放**——它们仍可恢复。",
        .stagedFailed: "%d 项暂存失败",
        .stagedFailedList: "失败项：%@",
        .releaseExplain: "要真正释放磁盘空间，请对暂存项执行 release（不可恢复）。",
        .releasing: "正在彻底释放 %d 项暂存文件…",
        .releasedResult: "已彻底释放 %d 项，释放 %@（按磁盘差值实测）。",
        .nothingStaged: "本次清单没有已暂存的项目。",
        .undoResult: "撤销完成：%d 项已还原到原路径。",
        .undoFailed: "%d 项无法还原",
        .undoNothing: "没有可撤销的暂存记录。",
        .manifestList: "暂存记录：",
        .manifestLine: "%@ · %@ · %d 项 · %@ · %@",
        .manifestStateStaged: "已暂存（可恢复）",
        .manifestStateReleased: "已彻底释放",
        .manifestStateUndone: "已撤销",
        .dryRunNote: "[dry run] 未移动任何文件。",
        .confirmRequired: "彻底释放需要显式加 --confirm-irreversible。",

        .refuseOutsideRoots: "已拒绝：%@ 不在允许的根目录内（%@）",
        .refuseProtected: "已拒绝：%@ 是受保护路径",
        .refuseSymlink: "已拒绝：%@ 是符号链接",
        .refuseNotRegular: "已拒绝：%@ 不是普通文件",
        .refuseTrashItself: "已拒绝：%@ 是废纸篓目录（或包含废纸篓）—— CachePilot 绝不把废纸篓移进自己",
        .refuseShowOnly: "已拒绝：%@ 是仅展示项，不可清理",
        .refuseNotFound: "已拒绝：%@ 不存在",
        .refuseNotStaged: "已拒绝：%@ 不是 CachePilot 暂存的",
        .refuseTargetExists: "已跳过：%@ 已存在，不覆盖",

        .catPackageManager: "包管理器缓存",
        .catAITools: "AI 工具残留",
        .catBrowserAutomation: "浏览器自动化",
        .catBuildArtifacts: "工程构建产物",
        .catAppCaches: "应用缓存（白名单）",
        .catGeneral: "通用",

        .kindVideo: "视频",
        .kindArchive: "压缩包",
        .kindInstaller: "安装包/磁盘映像",
        .kindModel: "AI 模型文件",
        .kindDocument: "文档",
        .kindData: "数据",
        .kindOther: "其他",
        .bigFilesNote: "大文件默认不勾选任何一项，请只勾你确认的编号。",

        .dupExact: "内容完全一致（哈希校验）",
        .dupLikely: "极可能一致（大小 + 首尾哈希）",
        .versionSuspect: "名称相近，疑似冗余版本；删除前请自行确认",
        .keepOldest: "最早的副本",
        .keepNewest: "最新的副本",

        .usage: """
        CachePilot — 面向 AI/开发者的磁盘瘦身工具（缓存规则 · 大文件 · 重复文件）

        用法：
          cachepilot plan    [--mode cache|big|dup|all] [--min-size 200MB] [--root 路径]... [--json] [--lang en|zh]
          cachepilot stage   --select 1,3-5 [--dry-run] [--lang en|zh]
          cachepilot release --confirm-irreversible [--manifest ID] [--lang en|zh]
          cachepilot undo    [--manifest ID] [--lang en|zh]
          cachepilot manifests
          cachepilot doctor

        安全：所有清理先移入废纸篓（可恢复）。只有显式执行 release 才会真正释放空间，
        且不可恢复。不在允许根目录、受保护路径、符号链接、仅展示项都会被拒绝。
        """,
        .doctorEnv: "语言：%@（来源：%@）",
        .doctorHome: "主目录：%@",
        .doctorTrash: "废纸篓目录：%@",
        .doctorManifest: "记录目录：%@",
        .doctorRules: "规则库：%d 条规则，schema v%d",
        .doctorRoots: "允许的根目录：%@",
        .doctorPlan: "最近清单：%@",

        .uiScan: "扫描",
        .uiRescan: "重新扫描",
        .uiScanning: "扫描中…（%@）",
        .uiCancel: "取消扫描",
        .uiCancelled: "已取消",
        .uiReady: "准备就绪",
        .uiSelectRecommended: "选建议项",
        .uiClearSelection: "清空勾选",
        .uiStage: "移入废纸篓（可恢复）",
        .uiStageTitle: "确认暂存",
        .uiStageMessage: "把 %d 项（%@）移入废纸篓？它们仍可从废纸篓恢复——此时空间还没释放。",
        .uiRelease: "彻底释放空间",
        .uiReleaseTitle: "永久删除暂存项？",
        .uiReleaseMessage: "将永久删除 %d 项暂存文件（%@），之后无法从废纸篓恢复。",
        .uiUndo: "撤销并还原",
        .uiStagedBanner: "已有 %@ 暂存在废纸篓、仍可恢复——磁盘空间尚未释放。",
        .uiFreedBanner: "已彻底释放 %d 项 · 释放 %@（实测）。",
        .uiFreeNow: "当前可用",
        .uiTabCache: "缓存规则",
        .uiTabBig: "大文件",
        .uiTabDup: "重复与冗余",
        .uiMinSize: "最小体积",
        .uiEmptyState: "点「扫描」看看这台机器能回收什么。",
        .uiRuleHint: "绿色为建议项（默认勾选），红色为仅展示项。",
        .uiBigHint: "这一页默认不勾选任何项，只勾你确认的编号。",
        .uiNotSelectable: "不可勾选",
        .uiFilterAll: "全部",
        .uiResultTitle: "执行结果",
        .uiOK: "好",
        .uiSelectByNumber: "按编号授权",
    ]

    /// 取文案。%@ 用 format(...) 填充。
    public static func t(_ key: Key, _ lang: Lang? = nil) -> String {
        let l = lang ?? current
        switch l {
        case .en: return key.rawValue
        case .zh: return zh[key] ?? key.rawValue   // 缺项回退英文
        }
    }

    public static func t(_ key: Key, _ args: CVarArg..., lang: Lang? = nil) -> String {
        String(format: t(key, lang), arguments: args)
    }

    /// 测试用：返回中文表里缺失的键（应为空）
    public static var missingZhKeys: [Key] {
        Key.allCases.filter { zh[$0] == nil }
    }
}

// MARK: - 体积/时间格式化（两种语言共用一个数学习惯）

public enum Fmt {
    public static func bytes(_ b: Int64) -> String {
        let gb = Double(b) / 1_073_741_824.0
        if gb >= 100 { return String(format: "%.0f GB", gb) }
        if gb >= 1 { return String(format: "%.1f GB", gb) }
        let mb = Double(b) / 1_048_576.0
        if mb >= 1 { return String(format: "%.0f MB", mb) }
        let kb = Double(b) / 1024.0
        return String(format: "%.0f KB", kb)
    }

    /// 解析 "200MB" / "1.5GB" / "800000"（默认 MB）
    public static func parseSizeMB(_ s: String) -> Double? {
        let t = s.trimmingCharacters(in: .whitespaces).uppercased()
        let units: [(String, Double)] = [("TB", 1_048_576), ("GB", 1024), ("MB", 1), ("KB", 1.0 / 1024), ("B", 1.0 / 1_048_576)]
        for (u, f) in units where t.hasSuffix(u) {
            let n = t.dropLast(u.count)
            if let v = Double(n) { return v * f }
            return nil
        }
        if let v = Double(t) { return v }
        return nil
    }

    public static func age(days: Int, lang: Lang) -> String {
        if days < 1 { return lang == .zh ? "今天" : "today" }
        return L10n.t(.days, days, lang: lang)
    }
}
