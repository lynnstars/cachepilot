import Foundation

// MARK: - 规则 JSON 模型（与 rules/cleanable_rules.json 对齐）

struct RulesFile: Codable {
    let schemaVersion: Int
    let categories: [String: String]
    let rules: [RuleItem]

    enum CodingKeys: String, CodingKey {
        case schemaVersion = "schema_version"
        case categories, rules
    }
}

struct RuleItem: Codable, Identifiable {
    let id: String
    let category: String
    let tool: String
    let name: String
    let risk: String
    let paths: [String]
    let minSizeMb: Double?
    let why: String
    let officialCmd: String?
    let defaultClean: Bool?
    let showOnly: Bool?

    enum CodingKeys: String, CodingKey {
        case id, category, tool, name, risk, paths, why
        case minSizeMb = "min_size_mb"
        case officialCmd = "official_cmd"
        case defaultClean = "default_clean"
        case showOnly = "show_only"
    }
}

// MARK: - 扫描结果模型

struct ScanItem: Identifiable {
    let id: String
    let tool: String
    let name: String
    let category: String
    let risk: String          // low / medium / high
    let sizeKB: Int64
    let paths: [String]       // 命中且存在的真实路径（用于清理）
    let why: String
    let officialCmd: String
    let defaultClean: Bool
    let showOnly: Bool

    var sizeText: String { Format.gb(sizeKB) }
    var canClean: Bool { !showOnly }
}

struct CatSection: Identifiable {
    let id: String
    let name: String
    let items: [ScanItem]
    var totalKB: Int64 { items.reduce(0) { $0 + $1.sizeKB } }
    var totalText: String { Format.gb(totalKB) }
}

// MARK: - 格式化

enum Format {
    static func gb(_ kb: Int64) -> String {
        let gb = Double(kb) / 1_048_576.0
        if gb >= 100 { return String(format: "%.0f GB", gb) }
        return String(format: "%.1f GB", gb)
    }

    static func riskText(_ risk: String) -> String {
        switch risk {
        case "low": return "🟢 低风险"
        case "medium": return "🟡 中风险"
        default: return "🔴 高风险"
        }
    }
}
