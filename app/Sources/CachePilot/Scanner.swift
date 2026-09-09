import Foundation

// MARK: - 扫描器（Swift 原生，逻辑与 scanner/scan.py 对齐）
// 只读：仅 du 统计大小，不删除任何文件。

enum Scanner {

    /// 从 bundle 读取规则库
    static func loadRules() -> [RuleItem] {
        guard let url = Bundle.main.url(forResource: "cleanable_rules", withExtension: "json"),
              let data = try? Data(contentsOf: url),
              let file = try? JSONDecoder().decode(RulesFile.self, from: data) else {
            return []
        }
        return file.rules
    }

    static func categoryName(_ id: String) -> String {
        guard let url = Bundle.main.url(forResource: "cleanable_rules", withExtension: "json"),
              let data = try? Data(contentsOf: url),
              let file = try? JSONDecoder().decode(RulesFile.self, from: data) else {
            return id
        }
        return file.categories[id] ?? id
    }

    private static func expand(_ p: String) -> String {
        p.replacingOccurrences(of: "~", with: NSHomeDirectory())
    }

    /// du -sk 取目录/文件 KB 数；不存在返回 0
    private static func duKB(_ path: String) -> Int64 {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/du")
        process.arguments = ["-sk", path]
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = Pipe()
        do {
            try process.run()
            process.waitUntilExit()
        } catch {
            return 0
        }
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        let text = String(data: data, encoding: .utf8) ?? ""
        guard let first = text.split(separator: "\t").first else { return 0 }
        return Int64(first) ?? 0
    }

    /// 磁盘可用字节
    static func freeBytes() -> Int64 {
        let home = NSHomeDirectory()
        let attrs = try? FileManager.default.attributesOfFileSystem(forPath: home)
        return (attrs?[.systemFreeSize] as? NSNumber)?.int64Value ?? 0
    }

    /// 全量扫描（同步，请在后台队列调用）
    static func scan(rules: [RuleItem], progress: (String) -> Void) -> [ScanItem] {
        var results: [ScanItem] = []
        for rule in rules where !rule.paths.isEmpty {
            progress("扫描 \(rule.tool) · \(rule.name)")
            var totalKB: Int64 = 0
            var hitPaths: [String] = []
            for raw in rule.paths {
                let path = expand(raw)
                if FileManager.default.fileExists(atPath: path) {
                    totalKB += duKB(path)
                    hitPaths.append(path)
                }
            }
            let minKB = Int64((rule.minSizeMb ?? 50) * 1024)
            if totalKB >= minKB {
                results.append(ScanItem(
                    id: rule.id,
                    tool: rule.tool,
                    name: rule.name,
                    category: rule.category,
                    risk: rule.risk,
                    sizeKB: totalKB,
                    paths: hitPaths,
                    why: rule.why,
                    officialCmd: rule.officialCmd ?? "",
                    defaultClean: rule.defaultClean ?? false,
                    showOnly: rule.showOnly ?? false
                ))
            }
        }
        return results.sorted { $0.sizeKB > $1.sizeKB }
    }

    // MARK: - 清理（移入废纸篓，可恢复）

    /// 将路径移入 ~/.Trash，冲突名自动加时间戳。返回成功移动数。
    @discardableResult
    static func trash(paths: [String]) -> (moved: Int, failed: [String]) {
        let fm = FileManager.default
        let trashDir = NSHomeDirectory() + "/.Trash"
        try? fm.createDirectory(atPath: trashDir, withIntermediateDirectories: true)
        let stamp = DateFormatter.trashStamp.string(from: Date())
        var moved = 0
        var failed: [String] = []
        for raw in paths {
            let url = URL(fileURLWithPath: raw)
            guard fm.fileExists(atPath: raw) else { continue }
            let dest = trashDir + "/" + url.lastPathComponent + "-CachePilot-" + stamp
            do {
                try fm.moveItem(atPath: raw, toPath: dest)
                moved += 1
            } catch {
                failed.append(raw)
            }
        }
        return (moved, failed)
    }

    /// 按类别分组（顺序：按规则首次出现）
    static func group(_ items: [ScanItem]) -> [CatSection] {
        var order: [String] = []
        var map: [String: [ScanItem]] = [:]
        for item in items {
            if map[item.category] == nil { order.append(item.category) }
            map[item.category, default: []].append(item)
        }
        return order.map { CatSection(id: $0, name: categoryName($0), items: map[$0] ?? []) }
    }
}

extension DateFormatter {
    static let trashStamp: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "yyyyMMdd-HHmmss"
        return f
    }()
}
