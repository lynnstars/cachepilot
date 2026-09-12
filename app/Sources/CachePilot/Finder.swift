import Foundation

// MARK: - A 类：缓存/依赖规则扫描（只读）
// 体积一律取「实占」（du -sk = 已分配块），稀疏文件/Docker.raw 不会虚报。

/// 可取消令牌（GUI 的取消按钮与 CLI 的中断共用）
public final class CancelToken {
    private let lock = NSLock()
    private var flag = false
    public init() {}
    public var isCancelled: Bool {
        lock.lock(); defer { lock.unlock() }
        return flag
    }
    public func cancel() {
        lock.lock(); flag = true; lock.unlock()
    }
}

public struct ScannedRule: Codable {
    public let ruleID: String
    public let category: String
    public let tool: String
    public let name: LocalizedText
    public let why: LocalizedText
    public let risk: String
    public let officialCmd: LocalizedText?
    public let hitPaths: [String]
    public let bytes: Int64
    public let preselect: Bool
    public let selectable: Bool
}

public enum RuleScanner {

    public static func expandPath(_ raw: String, home: String = NSHomeDirectory()) -> String {
        var p = raw
        if p == "~" { return home }
        if p.hasPrefix("~/") { p = home + String(p.dropFirst(1)) }
        p = p.replacingOccurrences(of: "$HOME", with: home)
        return p
    }

    public static func loadRules(at url: URL) throws -> RulesFile {
        let data = try Data(contentsOf: url)
        return try JSONDecoder().decode(RulesFile.self, from: data)
    }

    /// 默认规则库位置（按优先级）：
    /// 1) App bundle 资源  2) CACHEPILOT_RULES 环境变量  3) 可执行文件同级的 shared/rules
    /// 4) 用户数据目录（可热更新规则，不必发版）  5) 开发时从当前工作目录向上找 rules/
    public static func defaultRulesURL() -> URL? {
        if let u = Bundle.main.url(forResource: "cleanable_rules", withExtension: "json") { return u }
        let fm = FileManager.default
        var candidates: [String] = []
        if let env = ProcessInfo.processInfo.environment["CACHEPILOT_RULES"] { candidates.append(env) }
        let exe = URL(fileURLWithPath: CommandLine.arguments.first ?? ".").resolvingSymlinksInPath()
        let exeDir = exe.deletingLastPathComponent()
        candidates.append(exeDir.appendingPathComponent("cachepilot-rules.json").path)
        candidates.append(exeDir.appendingPathComponent("../shared/CachePilot/cleanable_rules.json").path)
        for c in candidates where fm.fileExists(atPath: c) { return URL(fileURLWithPath: c) }
        // 用户数据目录（规则热更新）
        let cfg = SafetyConfig.fromEnvironment()
        let userRules = cfg.dataDir + "/rules/cleanable_rules.json"
        if fm.fileExists(atPath: userRules) { return URL(fileURLWithPath: userRules) }
        // 开发：向上找仓库里的 rules/
        var dir = URL(fileURLWithPath: fm.currentDirectoryPath)
        for _ in 0..<6 {
            let c = dir.appendingPathComponent("rules/cleanable_rules.json")
            if fm.fileExists(atPath: c.path) { return c }
            dir = dir.deletingLastPathComponent()
        }
        return nil
    }

    /// du -sk 取实占字节；带超时（超时则 terminate 并返回 0，避免在满盘机器上卡死）
    @discardableResult
    public static func duBytes(_ path: String, timeout: Double = 90) -> Int64 {
        guard FileManager.default.fileExists(atPath: path) else { return 0 }
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/du")
        process.arguments = ["-sk", path]
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = Pipe()
        do { try process.run() } catch { return 0 }

        let done = DispatchSemaphore(value: 0)
        DispatchQueue.global(qos: .utility).async {
            process.waitUntilExit()
            done.signal()
        }
        if done.wait(timeout: .now() + timeout) == .timedOut {
            process.terminate()
            _ = done.wait(timeout: .now() + 2)
            return 0
        }
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        let text = String(data: data, encoding: .utf8) ?? ""
        guard let first = text.split(separator: "\t").first, let kb = Int64(first) else { return 0 }
        return kb * 1024
    }

    /// 并行扫描全部规则（每规则串行、规则之间并行 4 路）
    public static func scan(rules: RulesFile,
                            minSizeMBOverride: Double? = nil,
                            cancel: CancelToken? = nil,
                            progress: ((String) -> Void)? = nil) -> [ScannedRule] {
        let lock = NSLock()
        var out: [ScannedRule] = []
        let total = rules.rules.count
        let counter = Counter()

        DispatchQueue.concurrentPerform(iterations: total) { i in
            guard cancel?.isCancelled != true else { return }
            let rule = rules.rules[i]
            progress?(rule.name.text(L10n.current))
            var bytes: Int64 = 0
            var hits: [String] = []
            for raw in rule.paths {
                let p = expandPath(raw)
                guard FileManager.default.fileExists(atPath: p) else { continue }
                let b = duBytes(p)
                if b > 0 {
                    bytes += b
                    hits.append(p)
                }
            }
            let minBytes = Int64((minSizeMBOverride ?? rule.minMB) * 1_048_576)
            counter.tick()
            guard bytes >= minBytes, !hits.isEmpty else { return }
            let item = ScannedRule(
                ruleID: rule.id,
                category: rule.category,
                tool: rule.tool,
                name: rule.name,
                why: rule.why,
                risk: rule.risk,
                officialCmd: rule.officialCmd,
                hitPaths: hits,
                bytes: bytes,
                preselect: rule.risk == "low" && rule.isDefaultClean && !rule.isShowOnly,
                selectable: !rule.isShowOnly
            )
            lock.lock(); out.append(item); lock.unlock()
        }
        return out.sorted { $0.bytes > $1.bytes }
    }

    final class Counter {
        private let lock = NSLock()
        private var n = 0
        func tick() { lock.lock(); n += 1; lock.unlock() }
    }

    public static func categoryName(_ id: String, in file: RulesFile, lang: Lang) -> String {
        if let t = file.categories[id] { return t.text(lang) }
        switch id {
        case "package-manager": return L10n.t(.catPackageManager, lang)
        case "ai-tools": return L10n.t(.catAITools, lang)
        case "browser-automation": return L10n.t(.catBrowserAutomation, lang)
        case "build-artifacts": return L10n.t(.catBuildArtifacts, lang)
        case "app-caches": return L10n.t(.catAppCaches, lang)
        default: return L10n.t(.catGeneral, lang)
        }
    }
}

// MARK: - B 类：大文件 / 重复内容 / 冗余版本

public enum FileKind: String, Codable {
    case video, archive, installer, model, document, data, other

    public func text(_ lang: Lang) -> String {
        switch self {
        case .video: return L10n.t(.kindVideo, lang)
        case .archive: return L10n.t(.kindArchive, lang)
        case .installer: return L10n.t(.kindInstaller, lang)
        case .model: return L10n.t(.kindModel, lang)
        case .document: return L10n.t(.kindDocument, lang)
        case .data: return L10n.t(.kindData, lang)
        case .other: return L10n.t(.kindOther, lang)
        }
    }
}

public struct BigFile: Codable {
    public let path: String
    public let bytes: Int64
    public let mtime: Date
    public let kind: FileKind
    public var ageDays: Int { max(0, Int(Date().timeIntervalSince(mtime) / 86_400)) }
}

public struct FileGroup: Codable {
    public let id: String
    public let confidence: Confidence
    public let files: [BigFile]
    public let keepPath: String
    public var totalBytes: Int64 { files.reduce(0) { $0 + $1.bytes } }
    public var disposableBytes: Int64 { totalBytes - (files.first { $0.path == keepPath }?.bytes ?? 0) }
}

public enum BigFinder {

    /// 永不扫描/永不清理的目录（含系统敏感与隐私目录）
    public static let blockedDirNames: Set<String> = [
        ".ssh", ".gnupg", "Keychains", "AddressBook", "Messages", ".Trash",
        ".DocumentRevisions-V100", ".Spotlight-V100", ".fseventsd", ".TemporaryItems",
        "Photos Library.photoslibrary", "Mail", "Safari",
    ]

    public static let blockedPrefixes: [String] = [
        "/System", "/Library", "/Applications", "/usr", "/bin", "/sbin",
        "/private", "/etc", "/var", "/Volumes",
    ]

    /// 目录名带这些后缀 → 归类为工程依赖（node_modules 等），用于种类标记
    public static func kind(of path: String) -> FileKind {
        let ext = (path as NSString).pathExtension.lowercased()
        switch ext {
        case "mp4", "mov", "mkv", "avi", "webm", "flv", "m4v", "ts":
            return .video
        case "zip", "rar", "7z", "tar", "gz", "bz2", "xz", "tgz":
            return .archive
        case "dmg", "pkg", "iso", "msi", "exe":
            return .installer
        case "gguf", "safetensors", "pt", "pth", "onnx", "bin", "ckpt", "mlmodel", "ggml":
            return .model
        case "pdf", "doc", "docx", "ppt", "pptx", "xls", "xlsx", "key", "pages", "numbers":
            return .document
        case "csv", "json", "parquet", "sqlite", "db", "sql", "zipx", "bag":
            return .data
        default:
            return .other
        }
    }

    public static func isBlocked(_ path: String) -> Bool {
        let std = URL(fileURLWithPath: path).standardized.path
        for p in blockedPrefixes where std == p || std.hasPrefix(p + "/") { return true }
        for comp in std.split(separator: "/") {
            if blockedDirNames.contains(String(comp)) { return true }
        }
        return false
    }

    /// 遍历：只收普通文件（不跟符号链接），≥ minBytes，跳过黑名单
    public static func walk(roots: [String],
                            minBytes: Int64,
                            exclude: [String] = [],
                            maxSeconds: Double = 240,
                            cancel: CancelToken? = nil,
                            progress: ((Int, Int64) -> Void)? = nil) -> (files: [BigFile], truncated: Bool) {
        var files: [BigFile] = []
        var truncated = false
        let fm = FileManager.default
        let deadline = Date().addingTimeInterval(maxSeconds)
        let excluded = exclude.map { URL(fileURLWithPath: $0).standardized.path }

        let keys: [URLResourceKey] = [.isRegularFileKey, .fileSizeKey, .contentModificationDateKey, .isSymbolicLinkKey]
        for root in roots {
            let rootURL = URL(fileURLWithPath: (root as NSString).expandingTildeInPath).standardizedFileURL
            guard let en = fm.enumerator(at: rootURL,
                                        includingPropertiesForKeys: keys,
                                        options: [.skipsHiddenFiles, .skipsPackageDescendants],
                                        errorHandler: { _, _ in true }) else { continue }
            for case let url as URL in en {
                if cancel?.isCancelled == true { truncated = true; break }
                if Date() > deadline { truncated = true; break }
                let std = url.standardized.path
                if isBlocked(std) { en.skipDescendants(); continue }
                if excluded.contains(where: { std == $0 || std.hasPrefix($0 + "/") }) { en.skipDescendants(); continue }
                guard let v = try? url.resourceValues(forKeys: Set(keys)) else { continue }
                if v.isSymbolicLink == true { continue }
                guard v.isRegularFile == true else { continue }
                let size = Int64(v.fileSize ?? 0)
                guard size >= minBytes else { continue }
                files.append(BigFile(path: std,
                                     bytes: size,
                                     mtime: v.contentModificationDate ?? Date(),
                                     kind: kind(of: std)))
                progress?(files.count, size)
            }
            if truncated { break }
        }
        return (files.sorted { $0.bytes > $1.bytes }, truncated)
    }

    // MARK: 哈希（CryptoKit 流式；不可用时回退 shasum）

    static func hashFile(_ path: String, headTailOnly: Bool) -> String? {
        let fm = FileManager.default
        guard let attrs = try? fm.attributesOfItem(atPath: path),
              let size = (attrs[.size] as? NSNumber)?.int64Value else { return nil }
        guard let handle = FileHandle(forReadingAtPath: path) else { return nil }
        defer { try? handle.close() }

        if !headTailOnly || size <= 16 * 1_048_576 {
            return SHA256Hex.stream(read: { handle.readData(ofLength: $0) })
        }
        // 大小 + 首 8MB + 尾 8MB
        let chunk = 8 * 1_048_576
        let head = handle.readData(ofLength: chunk)
        try? handle.seek(toOffset: UInt64(size - Int64(chunk)))
        let tail = handle.readData(ofLength: chunk)
        var probe = Data("\(size):".utf8)
        probe.append(head); probe.append(tail)
        return SHA256Hex.of(probe)
    }

    /// 内容重复检测：先按大小分组 → 首尾哈希 → 大文件再全量哈希确认
    public static func duplicates(files: [BigFile],
                                  minBytes: Int64,
                                  exactVerifyLimit: Int64 = 2 * 1_073_741_824,
                                  cancel: CancelToken? = nil) -> [FileGroup] {
        var bySize: [Int64: [BigFile]] = [:]
        for f in files where f.bytes >= minBytes { bySize[f.bytes, default: []].append(f) }
        var groups: [FileGroup] = []
        for (_, cands) in bySize where cands.count > 1 {
            var byQuick: [String: [BigFile]] = [:]
            for f in cands {
                if cancel?.isCancelled == true { break }
                if let h = hashFile(f.path, headTailOnly: true) { byQuick[h, default: []].append(f) }
            }
            for (_, quickGroup) in byQuick where quickGroup.count > 1 {
                var solid: [BigFile] = []
                var confidence: Confidence = .exact
                if quickGroup.allSatisfy({ $0.bytes <= exactVerifyLimit }) {
                    var byFull: [String: [BigFile]] = [:]
                    for f in quickGroup {
                        if let h = hashFile(f.path, headTailOnly: false) { byFull[h, default: []].append(f) }
                    }
                    for (_, g) in byFull where g.count > 1 { solid.append(contentsOf: g) }
                } else {
                    solid = quickGroup
                    confidence = .likely
                }
                guard solid.count > 1 else { continue }
                let sorted = solid.sorted { $0.mtime < $1.mtime }
                let keep = sorted.first!.path
                groups.append(FileGroup(id: "dup:\(SHA256Hex.of(Data(keep.utf8)).prefix(12))",
                                        confidence: confidence,
                                        files: sorted,
                                        keepPath: keep))
            }
        }
        return groups.sorted { $0.disposableBytes > $1.disposableBytes }
    }

    /// 名称归一化：去掉 (1)/副本/copy/日期/字幕/横竖版/最新/最终/v1 等噪声
    public static func normalizeName(_ name: String) -> String {
        var s = name
        let ext = (s as NSString).pathExtension
        if !ext.isEmpty { s = (s as NSString).deletingPathExtension }
        let patterns = [
            #"[（(]\s*\d+\s*[)）]"#, #"[（(]\s*[a-zA-Z]\s*[)）]"#, #"(?i)\bcopy\b"#, #"副本"#,
            #"(?i)\bfinal\b"#, #"(?i)\bv\d+(\.\d+)*\b"#, #"第?\d+版"#, #"最终版?"#, #"最新版?"#,
            #"\d{4}[-_.]?\d{2}[-_.]?\d{2}"#, #"\d{6,8}"#, #"(有|无)字幕"#, #"(竖|横)版"#,
            #"(?i)\bhd\b"#, #"(?i)\b4k\b"#, #"[_\-\s]+"#,
        ]
        for p in patterns {
            s = s.replacingOccurrences(of: p, with: "", options: .regularExpression)
        }
        return s.trimmingCharacters(in: .whitespaces).lowercased()
    }

    /// 冗余版本：名称归一化后同名（同扩展名）且合计体积达阈值的组
    public static func redundantVersions(files: [BigFile], minGroupBytes: Int64) -> [FileGroup] {
        var byKey: [String: [BigFile]] = [:]
        for f in files {
            let base = (f.path as NSString).lastPathComponent
            let key = normalizeName(base) + "." + (base as NSString).pathExtension.lowercased()
            if normalizeName(base).isEmpty { continue }
            byKey[key, default: []].append(f)
        }
        var out: [FileGroup] = []
        for (key, group) in byKey where group.count > 1 {
            let total = group.reduce(Int64(0)) { $0 + $1.bytes }
            guard total >= minGroupBytes else { continue }
            let sorted = group.sorted { $0.mtime < $1.mtime }
            // 同名同大小 → 其实就是内容重复，交给 duplicates 处理，避免双重计数
            let sizes = Set(sorted.map { $0.bytes })
            if sizes.count == 1 { continue }
            out.append(FileGroup(id: "ver:\(SHA256Hex.of(Data(key.utf8)).prefix(12))",
                                 confidence: .suspect,
                                 files: sorted,
                                 keepPath: sorted.last!.path))
        }
        return out.sorted { $0.disposableBytes > $1.disposableBytes }
    }
}
