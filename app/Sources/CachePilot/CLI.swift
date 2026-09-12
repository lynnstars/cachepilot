import Foundation

// MARK: - 命令行接口（与 App 共用同一份内核：规则扫描 / 大文件 / 重复 / 暂存 / 释放 / 撤销）

public enum CLI {

    public static func run(args: [String], config: SafetyConfig? = nil) -> Int32 {
        var argv = args
        // 允许在任意位置指定 --lang；顺带忽略 macOS 传给可执行文件的 -AppleLanguages/-NS* 参数
        var langOverride: String? = nil
        var i = 0
        var cleaned: [String] = []
        while i < argv.count {
            if argv[i] == "--lang", i + 1 < argv.count {
                langOverride = argv[i + 1]; i += 2; continue
            }
            if argv[i].hasPrefix("-Apple") || argv[i].hasPrefix("-NS") {
                i += (i + 1 < argv.count && argv[i + 1].hasPrefix("(")) ? 2 : 1
                continue
            }
            cleaned.append(argv[i]); i += 1
        }
        argv = cleaned
        if let l = langOverride { L10n.current = L10n.resolve(preferred: [], env: l) }

        guard let cmd = argv.first else {
            print(L10n.t(.usage))
            return 2
        }
        let rest = Array(argv.dropFirst())
        let cfg = config ?? SafetyConfig.fromEnvironment(roots: parseRoots(rest))
        Actions.ensureDirs(cfg)

        switch cmd {
        case "plan", "scan":       return cmdPlan(rest, cfg)
        case "stage":              return cmdStage(rest, cfg)
        case "release":            return cmdRelease(rest, cfg)
        case "undo":               return cmdUndo(rest, cfg)
        case "manifests", "list":  return cmdManifests(cfg)
        case "doctor":             return cmdDoctor(cfg)
        case "version", "--version": print("CachePilot 0.4.0 (\(L10n.current.rawValue))"); return 0
        case "help", "--help", "-h": print(L10n.t(.usage)); return 0
        default:
            print("unknown command: \(cmd)\n")
            print(L10n.t(.usage))
            return 2
        }
    }

    // MARK: 参数工具

    static func value(_ args: [String], _ name: String) -> String? {
        guard let i = args.firstIndex(of: name), i + 1 < args.count else { return nil }
        return args[i + 1]
    }
    static func flag(_ args: [String], _ name: String) -> Bool { args.contains(name) }
    static func parseRoots(_ args: [String]) -> [String] {
        var out: [String] = []
        var i = 0
        while i < args.count {
            if args[i] == "--root", i + 1 < args.count { out.append(args[i + 1]); i += 2; continue }
            i += 1
        }
        return out
    }
    /// "1,3-5" → [1,3,4,5]
    static func parseNumbers(_ s: String) -> [Int] {
        var out: [Int] = []
        for part in s.split(separator: ",") {
            let t = part.trimmingCharacters(in: .whitespaces)
            if t.contains("-") {
                let bits = t.split(separator: "-").map { $0.trimmingCharacters(in: .whitespaces) }
                if bits.count == 2, let a = Int(bits[0]), let b = Int(bits[1]), a <= b {
                    out.append(contentsOf: a...b)
                }
            } else if let n = Int(t) { out.append(n) }
        }
        return Array(Set(out)).sorted()
    }

    // MARK: plan

    static func cmdPlan(_ args: [String], _ cfg: SafetyConfig) -> Int32 {
        var opt = ScanOptions()
        opt.mode = ScanMode.parse(value(args, "--mode"))
        if let s = value(args, "--min-size"), let mb = Fmt.parseSizeMB(s) { opt.minSizeMB = mb }
        if let s = value(args, "--dup-min-size"), let mb = Fmt.parseSizeMB(s) { opt.dupMinSizeMB = mb }
        if let s = value(args, "--version-min-size"), let mb = Fmt.parseSizeMB(s) { opt.versionMinGroupMB = mb }
        if let s = value(args, "--cache-min-size"), let mb = Fmt.parseSizeMB(s) { opt.cacheMinSizeOverride = mb }
        if let s = value(args, "--max-seconds"), let d = Double(s) { opt.maxWalkSeconds = d }
        let roots = parseRoots(args)
        if !roots.isEmpty { opt.roots = roots }
        if opt.mode != .cache { cfg.validateRootsForScan(opt.roots) }

        let cancel = CancelToken()
        var lastLine = ""
        let plan = Engine.buildPlan(options: opt, config: cfg, cancel: cancel, progress: { msg in
            if isatty(1) == 1 {
                FileHandle.standardError.write(("\r\u{1B}[K… " + msg).data(using: .utf8)!)
                lastLine = msg
            }
        })
        if isatty(1) == 1, !lastLine.isEmpty {
            FileHandle.standardError.write("\r\u{1B}[K".data(using: .utf8)!)
        }

        if flag(args, "--json") {
            let enc = JSONEncoder()
            enc.outputFormatting = [.prettyPrinted, .sortedKeys]
            enc.dateEncodingStrategy = .iso8601
            if let data = try? enc.encode(plan), let s = String(data: data, encoding: .utf8) { print(s) }
        } else {
            print(Engine.renderText(plan: plan, lang: L10n.current))
        }
        if !flag(args, "--no-save") {
            PlanStore.save(plan, config: cfg)
            if isatty(1) == 1 || flag(args, "--verbose") {
                print(L10n.t(.planSavedTo, cfg.planDir + "/latest.json"))
            }
        }
        return 0
    }

    // MARK: stage

    static func cmdStage(_ args: [String], _ cfg: SafetyConfig) -> Int32 {
        guard let sel = value(args, "--select") else {
            print(L10n.t(.usage)); return 2
        }
        let numbers = parseNumbers(sel)
        guard !numbers.isEmpty else { print(L10n.t(.noItems)); return 2 }

        let plan: Plan
        do { plan = try PlanStore.latest(config: cfg) } catch let e as SafetyError {
            print(e.description); return 1
        } catch { print(error.localizedDescription); return 1 }

        let picked = plan.entries(forNumbers: numbers)
        let missing = Set(numbers).subtracting(picked.map { $0.index })
        if !missing.isEmpty {
            print("⚠️ " + L10n.t(.refuseShowOnly, "\(missing.sorted())"))
        }
        let usable = picked.filter { $0.selectable }
        if usable.isEmpty { print(L10n.t(.noItems)); return 1 }

        let dry = flag(args, "--dry-run")
        print(L10n.t(.staging, usable.count, lang: L10n.current))
        let outcome = Engine.stage(plan: plan, numbers: usable.map { $0.index }, config: cfg, dryRun: dry)

        if dry {
            print(L10n.t(.dryRunNote))
            for item in outcome.manifest.items {
                print("  · \(item.originalPath) → \(item.stagedPath)")
            }
            return 0
        }
        print(L10n.t(.stagedResult, outcome.manifest.items.count,
                     Fmt.bytes(outcome.manifest.totalBytes), lang: L10n.current))
        if !outcome.failed.isEmpty {
            print(L10n.t(.stagedFailed, outcome.failed.count, lang: L10n.current))
            for (p, why) in outcome.failed { print("  · \(p): \(why)") }
        }
        print("")
        print(L10n.t(.releaseExplain))
        print("  cachepilot release --confirm-irreversible       # \(L10n.t(.irreversible))")
        print("  cachepilot undo                                # \(L10n.t(.recovered))")
        return 0
    }

    // MARK: release

    static func cmdRelease(_ args: [String], _ cfg: SafetyConfig) -> Int32 {
        let confirmed = flag(args, "--confirm-irreversible") || flag(args, "--yes")
        do {
            let r = try Actions.release(manifestID: value(args, "--manifest"),
                                        confirmed: confirmed,
                                        config: cfg)
            print(L10n.t(.releasedResult, r.count, Fmt.bytes(r.freedBytes), lang: L10n.current))
            let delta = Fmt.bytes(r.diskDelta < 0 ? -r.diskDelta : r.diskDelta)
            print("  disk delta: \(r.diskDelta >= 0 ? "+" : "-")\(delta)")
            for f in r.failed { print("  ⚠️ \(f)") }
            return 0
        } catch let e as SafetyError {
            print(e.description); return 1
        } catch {
            print(error.localizedDescription); return 1
        }
    }

    // MARK: undo

    static func cmdUndo(_ args: [String], _ cfg: SafetyConfig) -> Int32 {
        do {
            let r = try Actions.undo(manifestID: value(args, "--manifest"), config: cfg)
            print(L10n.t(.undoResult, r.restored, lang: L10n.current))
            if !r.failed.isEmpty {
                print(L10n.t(.undoFailed, r.failed.count, lang: L10n.current))
                for f in r.failed { print("  · \(f)") }
            }
            return 0
        } catch let e as SafetyError {
            print(e.description); return 1
        } catch {
            print(error.localizedDescription); return 1
        }
    }

    // MARK: manifests / doctor

    static func cmdManifests(_ cfg: SafetyConfig) -> Int32 {
        let all = Actions.manifests(config: cfg)
        guard !all.isEmpty else { print(L10n.t(.undoNothing)); return 0 }
        print(L10n.t(.manifestList))
        let df = ISO8601DateFormatter()
        for m in all {
            let state: String
            switch m.state {
            case .staged: state = L10n.t(.manifestStateStaged)
            case .released: state = L10n.t(.manifestStateReleased)
            case .undone, .partiallyUndone: state = L10n.t(.manifestStateUndone)
            }
            print(L10n.t(.manifestLine, m.id, df.string(from: m.createdAt),
                         m.items.count, Fmt.bytes(m.totalBytes), state, lang: L10n.current))
        }
        return 0
    }

    static func cmdDoctor(_ cfg: SafetyConfig) -> Int32 {
        let env = ProcessInfo.processInfo.environment["CACHEPILOT_LANG"]
        print(L10n.t(.doctorEnv, L10n.current.displayName, env == nil ? "system" : "CACHEPILOT_LANG", lang: L10n.current))
        print(L10n.t(.doctorHome, NSHomeDirectory(), lang: L10n.current))
        print(L10n.t(.doctorTrash, cfg.trashDir, lang: L10n.current))
        print(L10n.t(.doctorManifest, cfg.manifestDir, lang: L10n.current))
        print(L10n.t(.doctorRoots, cfg.allowedRoots.joined(separator: ", "), lang: L10n.current))
        if let url = RuleScanner.defaultRulesURL(), let rf = try? RuleScanner.loadRules(at: url) {
            print(L10n.t(.doctorRules, rf.rules.count, rf.schemaVersion, lang: L10n.current))
            let missing = rf.rules.filter { !$0.name.hasZh || !$0.why.hasZh }
            if !missing.isEmpty { print("⚠️ rules missing zh text: \(missing.map { $0.id })") }
        } else {
            print("⚠️ rule library not found")
        }
        if let p = try? PlanStore.latest(config: cfg, maxAgeMinutes: 24 * 60) {
            print(L10n.t(.doctorPlan, "\(p.id) · \(p.entries.count) items", lang: L10n.current))
        }
        let staged = Actions.stagedBytes(config: cfg)
        if staged.count > 0 {
            print(L10n.t(.uiStagedBanner, Fmt.bytes(staged.bytes), lang: L10n.current))
        }
        return 0
    }
}

extension SafetyConfig {
    /// 只允许在 home 或显式 --root 下扫描（扫描是只读的，这里仅做提示性校验）
    func validateRootsForScan(_ roots: [String]) {
        for r in roots {
            let std = URL(fileURLWithPath: (r as NSString).expandingTildeInPath).standardized.path
            if isProtected(std) {
                FileHandle.standardError.write((L10n.t(.refuseProtected, std) + "\n").data(using: .utf8)!)
            }
        }
    }
}
