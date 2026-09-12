import Foundation

// MARK: - 安全护栏 + 暂存 / 撤销 / 彻底释放

public enum SafetyError: Error, CustomStringConvertible, Equatable {
    case outsideRoots(path: String, roots: [String])
    case protectedPath(path: String)
    case symlink(path: String)
    case trashItself(path: String)
    case notFound(path: String)
    case notStaged(path: String)
    case targetExists(path: String)
    case confirmRequired
    case noPlan
    case stalePlan(ageMinutes: Int)

    public var description: String {
        switch self {
        case .outsideRoots(let p, let r):
            return L10n.t(.refuseOutsideRoots, p, r.joined(separator: ", "))
        case .protectedPath(let p): return L10n.t(.refuseProtected, p)
        case .symlink(let p):       return L10n.t(.refuseSymlink, p)
        case .trashItself(let p):   return L10n.t(.refuseTrashItself, p)
        case .notFound(let p):      return L10n.t(.refuseNotFound, p)
        case .notStaged(let p):     return L10n.t(.refuseNotStaged, p)
        case .targetExists(let p):  return L10n.t(.refuseTargetExists, p)
        case .confirmRequired:      return L10n.t(.confirmRequired)
        case .noPlan:               return L10n.t(.noItems)
        case .stalePlan(let m):     return "Plan is \(m) min old — re-run `cachepilot plan`."
        }
    }
}

public struct SafetyConfig {
    public let allowedRoots: [String]
    public let trashDir: String
    public let dataDir: String
    public let manifestDir: String
    public let planDir: String

    public init(allowedRoots: [String], trashDir: String, dataDir: String) {
        self.allowedRoots = allowedRoots.map { URL(fileURLWithPath: $0).standardized.path }
        self.trashDir = URL(fileURLWithPath: trashDir).standardized.path
        self.dataDir = URL(fileURLWithPath: dataDir).standardized.path
        self.manifestDir = self.dataDir + "/manifests"
        self.planDir = self.dataDir + "/plans"
    }

    public static func fromEnvironment(roots: [String] = []) -> SafetyConfig {
        let env = ProcessInfo.processInfo.environment
        let home = NSHomeDirectory()
        let trash = env["CACHEPILOT_TRASH_DIR"] ?? (home + "/.Trash")
        let data = env["CACHEPILOT_DATA_DIR"] ?? (home + "/Library/Application Support/CachePilot")
        // home 永远在允许根内；--root 只是追加扫描范围，不会缩小可清理范围
        var allowed = [home]
        for r in roots {
            let std = URL(fileURLWithPath: (r as NSString).expandingTildeInPath).standardized.path
            if !allowed.contains(std) { allowed.append(std) }
        }
        return SafetyConfig(allowedRoots: allowed, trashDir: trash, dataDir: data)
    }

    /// 系统敏感路径：永不触碰
    static let protectedPrefixes = [
        "/System", "/Library", "/Applications", "/usr", "/bin", "/sbin",
        "/private", "/etc", "/var", "/Volumes", "/opt", "/cores", "/dev",
    ]

    public func isProtected(_ std: String) -> Bool {
        for p in Self.protectedPrefixes where std == p || std.hasPrefix(p + "/") { return true }
        let home = NSHomeDirectory()
        let homeSensitive = [
            home + "/.ssh", home + "/.gnupg", home + "/Library/Keychains",
            home + "/Library/Messages", home + "/Library/Safari",
            home + "/Library/Application Support/AddressBook",
            dataDir,
        ]
        for p in homeSensitive where std == p || std.hasPrefix(p + "/") { return true }
        return false
    }

    public func isInsideRoots(_ std: String) -> Bool {
        allowedRoots.contains { std == $0 || std.hasPrefix($0 + "/") }
    }

    /// 核心校验：任何要移动的路径都必须过这一关
    public func validate(_ rawPath: String) throws -> String {
        let std = URL(fileURLWithPath: (rawPath as NSString).expandingTildeInPath).standardized.path
        let fm = FileManager.default

        // 1) 废纸篓（或它的祖先）绝不能被"移入废纸篓"——v0.3 的死循环 bug 在此彻底封死
        if std == trashDir || trashDir.hasPrefix(std + "/") {
            throw SafetyError.trashItself(path: std)
        }
        // 2) 受保护路径
        if isProtected(std) { throw SafetyError.protectedPath(path: std) }
        if std == NSHomeDirectory() { throw SafetyError.protectedPath(path: std) }
        // 3) 必须在允许的根目录内
        if !isInsideRoots(std) { throw SafetyError.outsideRoots(path: std, roots: allowedRoots) }
        // 4) 必须存在、且不是符号链接
        var isDir: ObjCBool = false
        guard fm.fileExists(atPath: std, isDirectory: &isDir) else { throw SafetyError.notFound(path: std) }
        if let attrs = try? fm.attributesOfItem(atPath: std),
           (attrs[.type] as? FileAttributeType) == .typeSymbolicLink {
            throw SafetyError.symlink(path: std)
        }
        return std
    }
}

public struct StageOutcome {
    public let manifest: Manifest
    public let failed: [(path: String, reason: String)]
}

public enum Actions {

    // MARK: 目录准备

    static func ensureDirs(_ cfg: SafetyConfig) {
        let fm = FileManager.default
        try? fm.createDirectory(atPath: cfg.trashDir, withIntermediateDirectories: true)
        try? fm.createDirectory(atPath: cfg.manifestDir, withIntermediateDirectories: true)
        try? fm.createDirectory(atPath: cfg.planDir, withIntermediateDirectories: true)
    }

    // MARK: 暂存（= 移入废纸篓，可恢复）

    /// targets: (原始路径, 字节数, 标签)
    public static func stage(targets: [(path: String, bytes: Int64, label: String)],
                             planID: String,
                             config: SafetyConfig,
                             dryRun: Bool = false) -> StageOutcome {
        ensureDirs(config)
        let fm = FileManager.default
        let stamp = ISO8601DateFormatter.compact.string(from: Date())
        let short = String(SHA256Hex.of(Data("\(planID)-\(stamp)".utf8)).prefix(6))
        let manifestID = "\(stamp)-\(short)"
        var items: [StagedItem] = []
        var failed: [(String, String)] = []

        for t in targets {
            do {
                let std = try config.validate(t.path)
                let name = (std as NSString).lastPathComponent
                var dest = "\(config.trashDir)/\(name)-CachePilot-\(short)"
                var n = 2
                while fm.fileExists(atPath: dest) {
                    dest = "\(config.trashDir)/\(name)-CachePilot-\(short)-\(n)"
                    n += 1
                }
                if dryRun {
                    items.append(StagedItem(originalPath: std, stagedPath: dest, sizeBytes: t.bytes, label: t.label))
                    continue
                }
                try fm.moveItem(atPath: std, toPath: dest)
                items.append(StagedItem(originalPath: std, stagedPath: dest, sizeBytes: t.bytes, label: t.label))
            } catch let e as SafetyError {
                failed.append((t.path, e.description))
            } catch {
                failed.append((t.path, error.localizedDescription))
            }
        }

        let manifest = Manifest(id: manifestID,
                                planID: planID,
                                createdAt: Date(),
                                state: .staged,
                                items: items,
                                releasedCount: nil,
                                releasedBytes: nil,
                                undoneCount: nil,
                                note: dryRun ? "dry-run" : nil)
        if !dryRun { saveManifest(manifest, config: config) }
        return StageOutcome(manifest: manifest, failed: failed)
    }

    // MARK: 彻底释放（不可恢复）

    public static func release(manifestID: String?,
                               confirmed: Bool,
                               config: SafetyConfig) throws -> (count: Int, freedBytes: Int64, diskDelta: Int64, failed: [String]) {
        guard confirmed else { throw SafetyError.confirmRequired }
        let manifest = try loadManifest(id: manifestID, config: config, requireState: .staged)
        let fm = FileManager.default
        let freeBefore = diskFreeBytes()
        var count = 0
        var freed: Int64 = 0
        var failed: [String] = []

        for item in manifest.items {
            let staged = URL(fileURLWithPath: item.stagedPath).standardized.path
            // 只允许删除「我们暂存到废纸篓里」的东西
            guard staged.hasPrefix(config.trashDir + "/") else {
                failed.append("\(item.stagedPath): \(SafetyError.notStaged(path: item.stagedPath).description)")
                continue
            }
            guard fm.fileExists(atPath: staged) else { continue }   // 用户已自行清空
            let measured = RuleScanner.duBytes(staged)
            do {
                try fm.removeItem(atPath: staged)
                count += 1
                freed += measured
            } catch {
                failed.append("\(staged): \(error.localizedDescription)")
            }
        }
        let freeAfter = diskFreeBytes()
        var updated = manifest
        updated.state = .released
        updated.releasedCount = count
        updated.releasedBytes = freed
        updated.note = "disk delta: \(freeAfter - freeBefore) bytes"
        saveManifest(updated, config: config)
        return (count, freed, freeAfter - freeBefore, failed)
    }

    // MARK: 撤销（还原到原路径）

    public static func undo(manifestID: String?,
                            config: SafetyConfig) throws -> (restored: Int, failed: [String]) {
        let manifest: Manifest
        if let id = manifestID {
            manifest = try loadManifest(id: id, config: config, requireState: nil)
        } else {
            manifest = try loadLatestManifest(config: config) { m in
                m.items.isEmpty == false && m.state != .undone && m.state != .released
            }
        }
        let fm = FileManager.default
        var restored = 0
        var failed: [String] = []

        for item in manifest.items {
            let staged = URL(fileURLWithPath: item.stagedPath).standardized.path
            guard staged.hasPrefix(config.trashDir + "/") else {
                failed.append("\(item.stagedPath): \(SafetyError.notStaged(path: item.stagedPath).description)")
                continue
            }
            guard fm.fileExists(atPath: staged) else {
                failed.append("\(item.originalPath): \(SafetyError.notFound(path: staged).description)")
                continue
            }
            if fm.fileExists(atPath: item.originalPath) {
                failed.append("\(item.originalPath): \(SafetyError.targetExists(path: item.originalPath).description)")
                continue
            }
            let parent = (item.originalPath as NSString).deletingLastPathComponent
            try? fm.createDirectory(atPath: parent, withIntermediateDirectories: true)
            do {
                try fm.moveItem(atPath: staged, toPath: item.originalPath)
                restored += 1
            } catch {
                failed.append("\(item.originalPath): \(error.localizedDescription)")
            }
        }
        var updated = manifest
        updated.state = failed.isEmpty ? .undone : .partiallyUndone
        updated.undoneCount = restored
        saveManifest(updated, config: config)
        return (restored, failed)
    }

    // MARK: 记录读写

    public static func saveManifest(_ m: Manifest, config: SafetyConfig) {
        ensureDirs(config)
        let url = URL(fileURLWithPath: config.manifestDir + "/\(m.id).json")
        let enc = JSONEncoder()
        enc.outputFormatting = [.prettyPrinted, .sortedKeys]
        enc.dateEncodingStrategy = .iso8601
        if let data = try? enc.encode(m) { try? data.write(to: url) }
    }

    public static func loadLatestManifest(config: SafetyConfig,
                                          where predicate: (Manifest) -> Bool) throws -> Manifest {
        let all = manifests(config: config)
        guard let m = all.first(where: predicate) else { throw SafetyError.noPlan }
        return m
    }

    public static func loadManifest(id: String?,
                                    config: SafetyConfig,
                                    requireState: ManifestState?) throws -> Manifest {
        if let id = id {
            let url = URL(fileURLWithPath: config.manifestDir + "/\(id).json")
            guard let data = try? Data(contentsOf: url) else { throw SafetyError.noPlan }
            return try decodeManifest(data)
        }
        return try loadLatestManifest(config: config) { m in
            requireState == nil || m.state == requireState!
        }
    }

    public static func manifests(config: SafetyConfig) -> [Manifest] {
        let fm = FileManager.default
        guard let files = try? fm.contentsOfDirectory(atPath: config.manifestDir) else { return [] }
        return files.filter { $0.hasSuffix(".json") }
            .compactMap { name -> Manifest? in
                guard let d = try? Data(contentsOf: URL(fileURLWithPath: config.manifestDir + "/" + name)) else { return nil }
                return try? decodeManifest(d)
            }
            .sorted { a, b in
                if a.createdAt != b.createdAt { return a.createdAt > b.createdAt }
                return a.id > b.id   // 同一秒内创建也要有确定顺序
            }
    }

    static func decodeManifest(_ data: Data) throws -> Manifest {
        let dec = JSONDecoder()
        dec.dateDecodingStrategy = .iso8601
        return try dec.decode(Manifest.self, from: data)
    }

    /// 当前仍躺在废纸篓里、由我们暂存的体积（GUI 顶部横幅用）
    public static func stagedBytes(config: SafetyConfig) -> (bytes: Int64, count: Int, manifestID: String?) {
        let fm = FileManager.default
        for m in manifests(config: config) where m.state == .staged {
            var bytes: Int64 = 0
            var n = 0
            for item in m.items where fm.fileExists(atPath: item.stagedPath) {
                bytes += item.sizeBytes
                n += 1
            }
            if n > 0 { return (bytes, n, m.id) }
        }
        return (0, 0, nil)
    }

    // MARK: 磁盘

    public static func diskFreeBytes() -> Int64 {
        let attrs = try? FileManager.default.attributesOfFileSystem(forPath: NSHomeDirectory())
        return (attrs?[.systemFreeSize] as? NSNumber)?.int64Value ?? 0
    }

    public static func diskTotalBytes() -> Int64 {
        let attrs = try? FileManager.default.attributesOfFileSystem(forPath: NSHomeDirectory())
        return (attrs?[.systemSize] as? NSNumber)?.int64Value ?? 0
    }
}

extension ISO8601DateFormatter {
    static let compact: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withYear, .withMonth, .withDay, .withTime, .withDashSeparatorInDate, .withColonSeparatorInTime]
        return f
    }()
}
