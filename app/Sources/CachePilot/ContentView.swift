import SwiftUI

struct ContentView: View {
    @State private var scanning = false
    @State private var cleaning = false
    @State private var sections: [CatSection] = []
    @State private var allItems: [ScanItem] = []
    @State private var selected = Set<String>()
    @State private var progressText = "准备就绪"
    @State private var scanned = false
    @State private var freeBytes: Int64 = 0
    @State private var showConfirm = false
    @State private var resultMessage: String?

    private var flatItems: [ScanItem] { sections.flatMap(\.items) }
    private var selectedKB: Int64 {
        flatItems.filter { selected.contains($0.id) }.reduce(0) { $0 + $1.sizeKB }
    }

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            if scanning {
                ProgressView(progressText).padding(24)
            } else if sections.isEmpty {
                emptyState
            } else {
                resultList
            }
            if scanned && !sections.isEmpty && !cleaning {
                bottomBar
            }
            if cleaning {
                ProgressView("移入废纸篓…").padding(10)
            }
        }
        .frame(minWidth: 760, minHeight: 560)
        .task { freeBytes = Scanner.freeBytes() }
        .alert("确认清理", isPresented: $showConfirm) {
            Button("取消", role: .cancel) {}
            Button("移入废纸篓", role: .destructive) { doClean() }
        } message: {
            Text("将移入废纸篓 \(selected.count) 项（\(Format.gb(selectedKB))），可从废纸篓恢复。")
        }
        .alert("清理结果", isPresented: Binding(
            get: { resultMessage != nil },
            set: { if !$0 { resultMessage = nil } }
        )) {
            Button("好") { resultMessage = nil; runScan(autoSelect: true) }
        } message: {
            Text(resultMessage ?? "")
        }
    }

    // MARK: - 头部

    private var header: some View {
        HStack(spacing: 12) {
            Image(systemName: "broom.and.shovel")
                .font(.system(size: 22))
                .foregroundStyle(.green)
            VStack(alignment: .leading, spacing: 2) {
                Text("CachePilot").font(.title3.bold())
                Text("面向 AI 工程师的依赖包/缓存清理")
                    .font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
            Text("可用 \(Format.gb(freeBytes / 1024))")
                .font(.callout.monospacedDigit())
                .padding(.horizontal, 10).padding(.vertical, 5)
                .background(.quaternary, in: Capsule())
            if scanned {
                Text("已扫描 · 可清理 \(Format.gb(totalKB))")
                    .font(.callout.monospacedDigit())
                    .padding(.horizontal, 10).padding(.vertical, 5)
                    .background(.green.opacity(0.15), in: Capsule())
            }
            Button(scanning ? "扫描中…" : "重新扫描") {
                runScan(autoSelect: true)
            }
            .buttonStyle(.borderedProminent)
            .disabled(scanning || cleaning)
        }
        .padding(14)
    }

    private var totalKB: Int64 { flatItems.reduce(0) { $0 + $1.sizeKB } }

    // MARK: - 空状态

    private var emptyState: some View {
        VStack(spacing: 12) {
            Spacer()
            Image(systemName: "opticaldiscdrive")
                .font(.system(size: 44)).foregroundStyle(.secondary)
            Text("点「扫描」看看这台机器的依赖缓存占用")
                .foregroundStyle(.secondary)
            Button("扫描") { runScan(autoSelect: true) }
                .buttonStyle(.borderedProminent)
            Spacer(); Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - 结果列表

    private var resultList: some View {
        List {
            ForEach(sections) { cat in
                Section {
                    ForEach(cat.items) { item in
                        ItemRow(item: item,
                                isSelected: selected.contains(item.id),
                                canSelect: item.canClean && !cleaning) {
                            toggle(item.id)
                        }
                    }
                } header: {
                    HStack {
                        Text(cat.name).font(.headline)
                        Spacer()
                        Text("可回收 \(cat.totalText)")
                            .font(.caption.monospacedDigit()).foregroundStyle(.green)
                    }
                }
            }
            Section {
                HStack {
                    Text("💡 所有清理先移入废纸篓（可恢复）。🟢 低风险默认勾选，🔴 仅展示项不可勾。")
                        .font(.caption).foregroundStyle(.secondary)
                }
            }
        }
        .listStyle(.inset)
    }

    // MARK: - 底部操作栏

    private var bottomBar: some View {
        HStack {
            Button {
                if selected.count == flatItems.filter(\.canClean).count {
                    selected = []
                } else {
                    selected = Set(flatItems.filter { $0.canClean && $0.defaultClean }.map(\.id))
                }
            } label: {
                Text(selected.count == flatItems.filter(\.canClean).count ? "取消全选" : "选建议项")
            }
            .disabled(cleaning)
            Spacer()
            Text("已选 \(selected.count) 项 · \(Format.gb(selectedKB))")
                .font(.callout.monospacedDigit())
            Button("移入废纸篓（可恢复）") { showConfirm = true }
                .buttonStyle(.borderedProminent)
                .tint(.orange)
                .disabled(selected.isEmpty || cleaning)
        }
        .padding(12)
        .background(.bar)
    }

    // MARK: - 动作

    private func toggle(_ id: String) {
        if selected.contains(id) { selected.remove(id) } else { selected.insert(id) }
    }

    private func runScan(autoSelect: Bool) {
        scanning = true
        progressText = "准备…"
        selected = []
        let rules = Scanner.loadRules()
        DispatchQueue.global(qos: .userInitiated).async {
            let items = Scanner.scan(rules: rules) { msg in
                DispatchQueue.main.async { progressText = msg }
            }
            DispatchQueue.main.async {
                allItems = items
                sections = Scanner.group(items)
                if autoSelect {
                    selected = Set(items.filter { $0.canClean && $0.defaultClean }.map(\.id))
                }
                freeBytes = Scanner.freeBytes()
                scanning = false
                scanned = true
                progressText = "完成"
            }
        }
    }

    private func doClean() {
        cleaning = true
        let items = flatItems.filter { selected.contains($0.id) }
        let paths = items.flatMap(\.paths)
        DispatchQueue.global(qos: .userInitiated).async {
            let result = Scanner.trash(paths: paths)
            DispatchQueue.main.async {
                cleaning = false
                let moved = result.moved
                let failed = result.failed.count
                var msg = "✅ 已移入废纸篓 \(moved) 个路径（可在废纸篓恢复）。"
                if failed > 0 { msg += "\n⚠️ \(failed) 个路径失败（可能无权限/被占用）：\n" + result.failed.prefix(5).joined(separator: "\n") }
                resultMessage = msg
                selected = []
            }
        }
    }
}

// MARK: - 单行

struct ItemRow: View {
    let item: ScanItem
    let isSelected: Bool
    let canSelect: Bool
    let onToggle: () -> Void

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Button(action: onToggle) {
                Image(systemName: isSelected ? "checkmark.circle.fill" : (canSelect ? "circle" : "circle.dashed"))
                    .font(.system(size: 18))
                    .foregroundStyle(isSelected ? Color.green : (canSelect ? Color.secondary : Color.gray.opacity(0.35)))
            }
            .buttonStyle(.plain)
            .disabled(!canSelect)
            .help(item.showOnly ? "仅展示项不可一键清理" : "点击勾选/取消")

            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 6) {
                    Text(item.name).font(.body.weight(.medium))
                    riskPill
                    if item.showOnly {
                        Text("仅展示").font(.caption2)
                            .padding(.horizontal, 6).padding(.vertical, 1)
                            .background(.red.opacity(0.15), in: Capsule())
                            .foregroundStyle(.red)
                    }
                }
                Text(item.why).font(.caption).foregroundStyle(.secondary)
                if !item.officialCmd.isEmpty {
                    Text("官方命令：\(item.officialCmd)")
                        .font(.caption2.monospaced())
                        .foregroundStyle(.tertiary)
                }
            }
            Spacer()
            VStack(alignment: .trailing, spacing: 2) {
                Text(item.sizeText).font(.body.monospacedDigit().weight(.semibold))
                Text(item.showOnly ? "需手动处理" : "可恢复")
                    .font(.caption2).foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 2)
        .opacity(isSelected ? 1 : (canSelect ? 0.85 : 1))
    }

    private var riskPill: some View {
        let color: Color = switch item.risk {
        case "low": .green
        case "medium": .yellow
        default: .red
        }
        return Text(Format.riskText(item.risk))
            .font(.caption2)
            .padding(.horizontal, 6).padding(.vertical, 1)
            .background(color.opacity(0.15), in: Capsule())
            .foregroundStyle(color)
    }
}
