import Foundation

// MARK: - 引擎：把 A（缓存规则）+ B（大文件/重复/冗余版本）合成一份「编号清单」

public enum ScanMode: String, CaseIterable {
    case cache, big, dup, all

    public static func parse(_ s: String?) -> ScanMode {
        guard let s = s?.lowercased() else { return .all }
        return ScanMode(rawValue: s) ?? .all
    }
}

public struct ScanOptions {
    public var mode: ScanMode = .all
    public var minSizeMB: Double = 200          // 大文件阈值
    public var dupMinSizeMB: Double = 50        // 重复检测阈值
    public var versionMinGroupMB: Double = 200  // 冗余版本组阈值
    public var roots: [String] = [NSHomeDirectory()]
    public var cacheMinSizeOverride: Double? = nil
    public var maxWalkSeconds: Double = 240

    public init() {}
}

public enum Engine {

    public static func buildPlan(options: ScanOptions,
                                 config: SafetyConfig,
                                 cancel: CancelToken? = nil,
                                 progress: ((String) -> Void)? = nil) -> Plan {
        var cacheEntries: [PlanEntry] = []
        var cacheHitPaths: [String] = []

        if options.mode == .cache || options.mode == .all {
            progress?(L10n.t(.sectionCache))
            if let url = RuleScanner.defaultRulesURL(), let rf = try? RuleScanner.loadRules(at: url) {
                let scanned = RuleScanner.scan(rules: rf,
                                               minSizeMBOverride: options.cacheMinSizeOverride,
                                               cancel: cancel,
                                               progress: { progress?($0) })
                cacheHitPaths = scanned.flatMap { $0.hitPaths }
                cacheEntries = scanned.map { s in
                    PlanEntry(index: 0, kind: .cacheRule, id: s.ruleID,
                              categoryKey: s.category,
                              title: s.name, detail: s.why, risk: s.risk,
                              confidence: .none, sizeBytes: s.bytes,
                              paths: s.hitPaths, keepPath: nil,
                              officialCmd: s.officialCmd,
                              preselect: s.preselect, selectable: s.selectable,
                              ageDays: nil)
                }
            }
        }

        var bigFiles: [BigFile] = []
        var walkTruncated = false
        if options.mode == .big || options.mode == .dup || options.mode == .all {
            progress?(L10n.t(.sectionBig))
            let minBytes = Int64(options.minSizeMB * 1_048_576)
            let exclude = cacheHitPaths + [config.trashDir, config.dataDir]
            let r = BigFinder.walk(roots: options.roots,
                                   minBytes: minBytes,
                                   exclude: exclude,
                                   maxSeconds: options.maxWalkSeconds,
                                   cancel: cancel,
                                   progress: { n, _ in progress?("\(L10n.t(.sectionBig)) · \(n)") })
            bigFiles = r.files
            walkTruncated = r.truncated
        }

        var dupEntries: [PlanEntry] = []
        var versionEntries: [PlanEntry] = []
        var dupMemberPaths = Set<String>()

        if options.mode == .dup || options.mode == .all {
            progress?(L10n.t(.sectionDuplicates))
            let dupMin = Int64(options.dupMinSizeMB * 1_048_576)
            let groups = BigFinder.duplicates(files: bigFiles, minBytes: dupMin, cancel: cancel)
            for g in groups {
                let disposables = g.files.filter { $0.path != g.keepPath }
                dupMemberPaths.formUnion(g.files.map { $0.path })
                let keepName = (g.keepPath as NSString).lastPathComponent
                dupEntries.append(PlanEntry(
                    index: 0, kind: .duplicate, id: g.id,
                    categoryKey: nil,
                    title: LocalizedText(en: "\(g.files.count) × \(keepName)",
                                         zh: "\(g.files.count) 份相同文件：\(keepName)"),
                    detail: LocalizedText(
                        en: g.confidence == .exact ? L10n.t(.dupExact, .en) : L10n.t(.dupLikely, .en),
                        zh: g.confidence == .exact ? L10n.t(.dupExact, .zh) : L10n.t(.dupLikely, .zh)),
                    risk: "medium", confidence: g.confidence,
                    sizeBytes: disposables.reduce(0) { $0 + $1.bytes },
                    paths: disposables.map { $0.path }, keepPath: g.keepPath,
                    officialCmd: nil, preselect: false, selectable: true, ageDays: nil))
            }

            progress?(L10n.t(.sectionVersions))
            let vGroups = BigFinder.redundantVersions(files: bigFiles,
                                                      minGroupBytes: Int64(options.versionMinGroupMB * 1_048_576))
            for g in vGroups {
                let disposables = g.files.filter { $0.path != g.keepPath }
                versionEntries.append(PlanEntry(
                    index: 0, kind: .redundantVersion, id: g.id,
                    categoryKey: nil,
                    title: LocalizedText(en: "\(g.files.count) similar versions",
                                         zh: "\(g.files.count) 个疑似冗余版本"),
                    detail: LocalizedText(en: L10n.t(.versionSuspect, .en), zh: L10n.t(.versionSuspect, .zh)),
                    risk: "medium", confidence: g.confidence,
                    sizeBytes: disposables.reduce(0) { $0 + $1.bytes },
                    paths: disposables.map { $0.path }, keepPath: g.keepPath,
                    officialCmd: nil, preselect: false, selectable: true, ageDays: nil))
            }
        }

        // 大文件章节：剔除已归入重复组的文件，避免同一条重复计数
        let bigEntries: [PlanEntry] = (options.mode == .big || options.mode == .all)
            ? bigFiles.filter { !dupMemberPaths.contains($0.path) }.map { f in
                PlanEntry(index: 0, kind: .bigFile, id: "big:\(SHA256Hex.of(Data(f.path.utf8)).prefix(12))",
                          categoryKey: nil,
                          title: LocalizedText(en: (f.path as NSString).lastPathComponent,
                                               zh: (f.path as NSString).lastPathComponent),
                          detail: LocalizedText(en: f.kind.text(.en), zh: f.kind.text(.zh)),
                          risk: "medium", confidence: .none, sizeBytes: f.bytes,
                          paths: [f.path], keepPath: nil, officialCmd: nil,
                          preselect: false, selectable: true, ageDays: f.ageDays)
            }
            : []

        var entries = cacheEntries.sorted { $0.sizeBytes > $1.sizeBytes }
            + bigEntries.sorted { $0.sizeBytes > $1.sizeBytes }
            + dupEntries.sorted { $0.sizeBytes > $1.sizeBytes }
            + versionEntries.sorted { $0.sizeBytes > $1.sizeBytes }

        // 统一编号（1-based，稳定；授权按编号）
        entries = entries.enumerated().map { i, e in
            PlanEntry(index: i + 1, kind: e.kind, id: e.id, categoryKey: e.categoryKey,
                      title: e.title, detail: e.detail, risk: e.risk, confidence: e.confidence,
                      sizeBytes: e.sizeBytes, paths: e.paths, keepPath: e.keepPath,
                      officialCmd: e.officialCmd, preselect: e.preselect,
                      selectable: e.selectable, ageDays: e.ageDays)
        }

        let stamp = ISO8601DateFormatter.compact.string(from: Date())
        let plan = Plan(id: stamp + "-" + String(SHA256Hex.of(Data(entries.map { $0.id }.joined().utf8)).prefix(6)),
                        createdAt: Date(),
                        lang: L10n.current,
                        mode: walkTruncated ? options.mode.rawValue + "+truncated" : options.mode.rawValue,
                        minSizeMB: options.minSizeMB,
                        roots: options.roots,
                        entries: entries,
                        scannedAt: Date(),
                        diskTotalBytes: Actions.diskTotalBytes(),
                        diskFreeBytes: Actions.diskFreeBytes())
        return plan
    }

    /// 按编号暂存（授权 → 移入废纸篓）
    public static func stage(plan: Plan,
                             numbers: [Int],
                             config: SafetyConfig,
                             dryRun: Bool = false) -> StageOutcome {
        let picked = plan.entries(forNumbers: numbers)
        var targets: [(path: String, bytes: Int64, label: String)] = []
        for e in picked {
            for p in e.paths {
                // 每条路径按条目均摊体积，仅用于展示
                let share = e.paths.isEmpty ? 0 : e.sizeBytes / Int64(e.paths.count)
                targets.append((p, share, e.titleText))
            }
        }
        return Actions.stage(targets: targets, planID: plan.id, config: config, dryRun: dryRun)
    }

    // MARK: 文本报告（CLI）

    public static func renderText(plan: Plan, lang: Lang) -> String {
        var out: [String] = []
        out.append(L10n.t(.reportTitle, plan.id, lang: lang))
        let pct = plan.diskTotalBytes > 0
            ? String(format: "%.0f%%", Double(plan.diskTotalBytes - plan.diskFreeBytes) / Double(plan.diskTotalBytes) * 100)
            : "?"
        out.append(L10n.t(.diskLine, Fmt.bytes(plan.diskTotalBytes - plan.diskFreeBytes),
                          Fmt.bytes(plan.diskFreeBytes), pct, lang: lang))
        out.append("")
        out.append(L10n.t(.scannedSummary, plan.entries.count,
                          Fmt.bytes(plan.totalSelectableBytes),
                          Fmt.bytes(plan.totalShowOnlyBytes), lang: lang))
        out.append("")

        var currentKind: EntryKind? = nil
        for e in plan.entries {
            if currentKind != e.kind {
                currentKind = e.kind
                out.append(String(repeating: "─", count: 72))
                out.append(sectionTitle(e.kind, lang: lang))
                out.append(String(repeating: "─", count: 72))
            }
            let risk = riskText(e.risk, e.selectable, lang: lang)
            let num = String(format: "%3d", e.index)
            out.append("[\(num)] \(Fmt.bytes(e.sizeBytes))  \(risk)  \(e.title.text(lang))")
            if e.kind == .cacheRule {
                out.append("      " + L10n.t(.itemWhy, e.detail.text(lang), lang: lang))
                if let cmd = e.officialCmd {
                    out.append("      " + L10n.t(.itemOfficialCmd, cmd.text(lang), lang: lang))
                }
            } else {
                out.append("      " + e.detail.text(lang))
            }
            if let k = e.keepPath {
                out.append("      " + L10n.t(.itemKeepHint, k, lang: lang))
            }
            if let age = e.ageDays, e.kind != .cacheRule {
                out.append("      " + L10n.t(.itemAge, Fmt.age(days: age, lang: lang), lang: lang))
            }
            if e.kind == .cacheRule {
                out.append("      " + L10n.t(.itemPaths, e.paths.joined(separator: "  "), lang: lang))
            } else {
                for p in e.paths { out.append("      · " + p) }
            }
            if !e.selectable { out.append("      ⚠️ " + L10n.t(.showOnlyNote, lang: lang)) }
        }

        out.append("")
        out.append(L10n.t(.totalSelectable, Fmt.bytes(plan.totalSelectableBytes), lang: lang))
        if plan.totalShowOnlyBytes > 0 {
            out.append(L10n.t(.totalShowOnly, Fmt.bytes(plan.totalShowOnlyBytes), lang: lang))
        }
        out.append(L10n.t(.planHint, lang: lang))
        if plan.mode.hasSuffix("+truncated") {
            out.append("⚠️ scan truncated (time budget) — increase --max-seconds or narrow --root")
        }
        return out.joined(separator: "\n")
    }

    public static func sectionTitle(_ kind: EntryKind, lang: Lang) -> String {
        switch kind {
        case .cacheRule:        return L10n.t(.sectionCache, lang: lang)
        case .bigFile:          return L10n.t(.sectionBig, lang: lang)
        case .duplicate:        return L10n.t(.sectionDuplicates, lang: lang)
        case .redundantVersion: return L10n.t(.sectionVersions, lang: lang)
        }
    }

    public static func riskText(_ risk: String, _ selectable: Bool, lang: Lang) -> String {
        if !selectable { return "🔴 " + L10n.t(.riskShowOnly, lang: lang) }
        switch risk {
        case "low":    return "🟢 " + L10n.t(.riskLow, lang: lang)
        case "medium": return "🟡 " + L10n.t(.riskMedium, lang: lang)
        default:       return "🔴 " + L10n.t(.riskHigh, lang: lang)
        }
    }
}

// MARK: - 清单落盘（--select 编号必须对应同一份清单）

public enum PlanStore {

    public static func save(_ plan: Plan, config: SafetyConfig) {
        Actions.ensureDirs(config)
        let enc = JSONEncoder()
        enc.outputFormatting = [.prettyPrinted, .sortedKeys]
        enc.dateEncodingStrategy = .iso8601
        guard let data = try? enc.encode(plan) else { return }
        try? data.write(to: URL(fileURLWithPath: config.planDir + "/\(plan.id).json"))
        try? data.write(to: URL(fileURLWithPath: config.planDir + "/latest.json"))
    }

    public static func latest(config: SafetyConfig, maxAgeMinutes: Int = 60) throws -> Plan {
        let url = URL(fileURLWithPath: config.planDir + "/latest.json")
        guard let data = try? Data(contentsOf: url) else { throw SafetyError.noPlan }
        let dec = JSONDecoder()
        dec.dateDecodingStrategy = .iso8601
        let plan = try dec.decode(Plan.self, from: data)
        let age = Int(Date().timeIntervalSince(plan.createdAt) / 60)
        if age > maxAgeMinutes { throw SafetyError.stalePlan(ageMinutes: age) }
        return plan
    }
}
