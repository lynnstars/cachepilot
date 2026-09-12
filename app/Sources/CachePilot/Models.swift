import Foundation

// MARK: - 规则库（schema v2：所有面向用户的文案都是 {en, zh}）

/// 双语文本。英文必填，中文缺失时回退英文。
public struct LocalizedText: Codable, Equatable {
    public let en: String
    public let zh: String?

    public init(en: String, zh: String? = nil) {
        self.en = en
        self.zh = zh
    }

    public init(from decoder: Decoder) throws {
        // 兼容纯字符串写法（老规则或第三方贡献者只写英文）
        let c = try decoder.singleValueContainer()
        if let s = try? c.decode(String.self) {
            self.en = s; self.zh = nil; return
        }
        let k = try decoder.container(keyedBy: CodingKeys.self)
        self.en = try k.decode(String.self, forKey: .en)
        self.zh = try k.decodeIfPresent(String.self, forKey: .zh)
    }

    public func encode(to encoder: Encoder) throws {
        var k = encoder.container(keyedBy: CodingKeys.self)
        try k.encode(en, forKey: .en)
        try k.encodeIfPresent(zh, forKey: .zh)
    }

    enum CodingKeys: String, CodingKey { case en, zh }

    public func text(_ lang: Lang) -> String {
        switch lang {
        case .en: return en
        case .zh: return zh ?? en
        }
    }

    /// 是否缺中文（doctor / 测试用）
    public var hasZh: Bool { !(zh ?? "").isEmpty }
}

public struct RulesFile: Codable {
    public let schemaVersion: Int
    public let categories: [String: LocalizedText]
    public let rules: [RuleItem]

    enum CodingKeys: String, CodingKey {
        case schemaVersion = "schema_version"
        case categories, rules
    }
}

public struct RuleItem: Codable, Identifiable, Equatable {
    public let id: String
    public let category: String
    public let tool: String
    public let name: LocalizedText
    public let risk: String              // low / medium / high
    public let paths: [String]
    public let minSizeMb: Double?
    public let why: LocalizedText
    public let officialCmd: LocalizedText?
    public let defaultClean: Bool?
    public let showOnly: Bool?

    enum CodingKeys: String, CodingKey {
        case id, category, tool, name, risk, paths, why
        case minSizeMb = "min_size_mb"
        case officialCmd = "official_cmd"
        case defaultClean = "default_clean"
        case showOnly = "show_only"
    }

    public var isShowOnly: Bool { showOnly ?? false }
    public var isDefaultClean: Bool { defaultClean ?? false }
    public var minMB: Double { minSizeMb ?? 50 }
}

// MARK: - 清单条目（编号授权的最小单位）

public enum EntryKind: String, Codable {
    case cacheRule        // A：缓存/依赖规则
    case bigFile          // B：大文件
    case duplicate        // B：内容重复
    case redundantVersion // B：名称相近的冗余版本
}

public enum Confidence: String, Codable {
    case exact     // 哈希校验一致
    case likely    // 大小 + 首尾哈希
    case suspect   // 名称启发式
    case none
}

/// 一条可授权条目：用户看到的就是它，编号也是它的索引。
public struct PlanEntry: Codable, Identifiable {
    public let index: Int              // 1-based 编号（授权用）
    public let kind: EntryKind
    public let id: String              // 稳定 id（rule id / 文件组 id）
    public let categoryKey: String?    // 缓存规则的 category
    public let title: LocalizedText
    public let detail: LocalizedText
    public let risk: String
    public let confidence: Confidence
    public let sizeBytes: Int64
    public let paths: [String]         // 会被移动的路径（必须逐条可见）
    public let keepPath: String?       // 重复组建议保留的文件
    public let officialCmd: LocalizedText?
    public let preselect: Bool         // 是否建议项（缓存 low + default_clean）
    public let selectable: Bool        // false = 仅展示，永不清理
    public let ageDays: Int?

    public var titleText: String { title.text(L10n.current) }
    public var detailText: String { detail.text(L10n.current) }
}

public struct Plan: Codable {
    public let id: String
    public let createdAt: Date
    public let lang: Lang
    public let mode: String
    public let minSizeMB: Double
    public let roots: [String]
    public let entries: [PlanEntry]
    public let scannedAt: Date
    public let diskTotalBytes: Int64
    public let diskFreeBytes: Int64

    public var selectableEntries: [PlanEntry] { entries.filter { $0.selectable } }
    public var totalSelectableBytes: Int64 { selectableEntries.reduce(0) { $0 + $1.sizeBytes } }
    public var totalShowOnlyBytes: Int64 { entries.filter { !$0.selectable }.reduce(0) { $0 + $1.sizeBytes } }

    public func entries(forNumbers numbers: [Int]) -> [PlanEntry] {
        let set = Set(numbers)
        return entries.filter { set.contains($0.index) }
    }
}

// MARK: - 暂存 / 释放 / 撤销记录

public struct StagedItem: Codable {
    public let originalPath: String
    public let stagedPath: String
    public let sizeBytes: Int64
    public let label: String
}

public enum ManifestState: String, Codable {
    case staged
    case released
    case undone
    case partiallyUndone
}

public struct Manifest: Codable {
    public let id: String
    public let planID: String
    public let createdAt: Date
    public var state: ManifestState
    public var items: [StagedItem]
    public var releasedCount: Int?
    public var releasedBytes: Int64?
    public var undoneCount: Int?
    public var note: String?

    public var totalBytes: Int64 { items.reduce(0) { $0 + $1.sizeBytes } }
}
