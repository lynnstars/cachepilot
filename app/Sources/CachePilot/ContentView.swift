import SwiftUI

// MARK: - v0.4 界面：缓存规则（A）+ 大文件/重复/冗余（B），两段式清理（暂存 → 彻底释放）+ 撤销

struct ContentView: View {
    @State private var lang: Lang = L10n.current
    @State private var plan: Plan?
    @State private var selected: Set<Int> = []
    @State private var scanning = false
    @State private var working = false
    @State private var progressText = L10n.t(.uiReady)
    @State private var cancelToken = CancelToken()
    @State private var minSizeMB: Double = 200
    @State private var tab: Int = 0
    @State private var freeBytes: Int64 = 0
    @State private var staged: (bytes: Int64, count: Int, manifestID: String?) = (0, 0, nil)
    @State private var resultMessage: String?
    @State private var showStageConfirm = false
    @State private var showReleaseConfirm = false

    private let cfg = SafetyConfig.fromEnvironment()

    private func t(_ k: L10n.Key) -> String { L10n.t(k, lang) }
    private func t(_ k: L10n.Key, _ a: CVarArg...) -> String { String(format: L10n.t(k, lang), arguments: a) }

    // MARK: 当前页的条目
    private var visibleEntries: [PlanEntry] {
        guard let p = plan else { return [] }
        switch tab {
        case 0: return p.entries.filter { $0.kind == .cacheRule }
        case 1: return p.entries.filter { $0.kind == .bigFile }
        default: return p.entries.filter { $0.kind == .duplicate || $0.kind == .redundantVersion }
        }
    }
    private var selectedEntries: [PlanEntry] {
        guard let p = plan else { return [] }
        return p.entries.filter { selected.contains($0.index) }
    }
    private var selectedBytes: Int64 { selectedEntries.reduce(0) { $0 + $1.sizeBytes } }

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            if let msg = resultMessage {
                banner(text: msg, tint: .green)
            }
            if staged.count > 0 {
                stagedBanner
            }
            content
            if plan != nil && !scanning { bottomBar }
        }
        .frame(minWidth: 900, minHeight: 620)
        .task { refreshDiskState() }
        .alert(t(.uiStageTitle), isPresented: $showStageConfirm) {
            Button(t(.uiCancel), role: .cancel) {}
            Button(t(.uiStage), role: .destructive) { doStage() }
        } message: {
            Text(t(.uiStageMessage, selectedEntries.count, Fmt.bytes(selectedBytes)))
        }
        .alert(t(.uiReleaseTitle), isPresented: $showReleaseConfirm) {
            Button(t(.uiCancel), role: .cancel) {}
            Button(t(.uiRelease), role: .destructive) { doRelease() }
        } message: {
            Text(t(.uiReleaseMessage, staged.count, Fmt.bytes(staged.bytes)))
        }
    }

    // MARK: 头部

    private var header: some View {
        VStack(spacing: 8) {
            HStack(spacing: 12) {
                Image(systemName: "broom.and.shovel").font(.system(size: 22)).foregroundStyle(.green)
                VStack(alignment: .leading, spacing: 2) {
                    Text("CachePilot").font(.title3.bold())
                    Text(t(.appTagline)).font(.caption).foregroundStyle(.secondary)
                }
                Spacer()
                Text("\(t(.uiFreeNow)) \(Fmt.bytes(freeBytes))")
                    .font(.callout.monospacedDigit())
                    .padding(.horizontal, 10).padding(.vertical, 5)
                    .background(.quaternary, in: Capsule())
                languageMenu
                Button(scanning ? t(.uiScanning, progressText) : (plan == nil ? t(.uiScan) : t(.uiRescan))) {
                    runScan()
                }
                .buttonStyle(.borderedProminent)
                .disabled(scanning || working)
                if scanning {
                    Button(t(.uiCancel)) { cancelToken.cancel() }
                }
            }
            HStack(spacing: 14) {
                Picker("", selection: $tab) {
                    Text("\(t(.uiTabCache)) (\(plan?.entries.filter { $0.kind == .cacheRule }.count ?? 0))").tag(0)
                    Text("\(t(.uiTabBig)) (\(plan?.entries.filter { $0.kind == .bigFile }.count ?? 0))").tag(1)
                    Text("\(t(.uiTabDup)) (\(plan?.entries.filter { $0.kind == .duplicate || $0.kind == .redundantVersion }.count ?? 0))").tag(2)
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .frame(maxWidth: 460)
                Spacer()
                Text(t(.uiMinSize)).font(.caption).foregroundStyle(.secondary)
                Picker("", selection: $minSizeMB) {
                    Text("100 MB").tag(100.0)
                    Text("200 MB").tag(200.0)
                    Text("500 MB").tag(500.0)
                    Text("1 GB").tag(1024.0)
                }
                .labelsHidden().frame(width: 110)
                .onChange(of: minSizeMB) { _, _ in if plan != nil { runScan() } }
                if let p = plan {
                    Text(t(.scannedSummary, p.entries.count,
                           Fmt.bytes(p.totalSelectableBytes), Fmt.bytes(p.totalShowOnlyBytes)))
                        .font(.caption).foregroundStyle(.secondary)
                }
            }
        }
        .padding(.horizontal, 14).padding(.vertical, 10)
    }

    private var languageMenu: some View {
        Menu {
            Button("跟随系统 / Follow system") { setLang(nil) }
            Button("English") { setLang("en") }
            Button("中文") { setLang("zh") }
        } label: {
            Label(lang.displayName, systemImage: "globe")
        }
        .menuStyle(.borderlessButton)
        .fixedSize()
    }

    private func setLang(_ override: String?) {
        if let o = override {
            UserDefaults.standard.set(o, forKey: "langOverride")
            L10n.current = L10n.resolve(preferred: [], env: o)
        } else {
            UserDefaults.standard.removeObject(forKey: "langOverride")
            L10n.current = L10n.resolve()
        }
        lang = L10n.current
    }

    // MARK: 内容

    @ViewBuilder
    private var content: some View {
        if scanning {
            VStack(spacing: 10) {
                ProgressView()
                Text(t(.uiScanning, progressText)).font(.callout).foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if plan == nil {
            VStack(spacing: 12) {
                Spacer()
                Image(systemName: "opticaldiscdrive").font(.system(size: 44)).foregroundStyle(.secondary)
                Text(t(.uiEmptyState)).foregroundStyle(.secondary)
                Button(t(.uiScan)) { runScan() }.buttonStyle(.borderedProminent)
                Spacer(); Spacer()
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if visibleEntries.isEmpty {
            VStack(spacing: 8) {
                Spacer()
                Text(t(.noItems)).foregroundStyle(.secondary)
                Spacer(); Spacer()
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            List {
                Section {
                    ForEach(visibleEntries) { e in
                        EntryRow(entry: e, lang: lang,
                                 isSelected: selected.contains(e.index),
                                 onToggle: { toggle(e) })
                    }
                } header: {
                    HStack {
                        Text(tab == 0 ? t(.uiRuleHint) : t(.uiBigHint)).font(.caption)
                        Spacer()
                    }
                }
            }
            .listStyle(.inset)
        }
    }

    private func banner(text: String, tint: Color) -> some View {
        HStack {
            Text(text).font(.callout)
            Spacer()
            Button(t(.uiOK)) { resultMessage = nil }.buttonStyle(.borderless)
        }
        .padding(10)
        .background(tint.opacity(0.12))
    }

    /// 关键横幅：暂存 ≠ 释放空间。彻底释放或撤销，都在这里。
    private var stagedBanner: some View {
        HStack(spacing: 12) {
            Image(systemName: "tray.full").foregroundStyle(.orange)
            Text(t(.uiStagedBanner, Fmt.bytes(staged.bytes))).font(.callout)
            Spacer()
            Button(t(.uiRelease)) { showReleaseConfirm = true }
                .buttonStyle(.borderedProminent).tint(.red)
                .disabled(working)
            Button(t(.uiUndo)) { doUndo() }.disabled(working)
        }
        .padding(10)
        .background(Color.orange.opacity(0.12))
    }

    // MARK: 底部操作栏

    private var bottomBar: some View {
        HStack(spacing: 12) {
            Button(t(.uiSelectRecommended)) {
                guard let p = plan else { return }
                selected = Set(p.entries.filter { $0.preselect }.map { $0.index })
                tab = 0
            }
            Button(t(.uiClearSelection)) { selected = [] }
            Spacer()
            Text("\(selectedEntries.count) · \(Fmt.bytes(selectedBytes))")
                .font(.callout.monospacedDigit())
            Button(t(.uiStage)) { showStageConfirm = true }
                .buttonStyle(.borderedProminent).tint(.orange)
                .disabled(selected.isEmpty || working || scanning)
        }
        .padding(12)
        .background(.bar)
    }

    // MARK: 动作

    private func toggle(_ e: PlanEntry) {
        guard e.selectable else { return }
        if selected.contains(e.index) { selected.remove(e.index) } else { selected.insert(e.index) }
    }

    private func refreshDiskState() {
        freeBytes = Actions.diskFreeBytes()
        staged = Actions.stagedBytes(config: cfg)
    }

    private func runScan() {
        scanning = true
        selected = []
        resultMessage = nil
        cancelToken = CancelToken()
        let token = cancelToken
        progressText = t(.uiReady)
        var opt = ScanOptions()
        opt.mode = .all
        opt.minSizeMB = minSizeMB
        let theLang = lang
        DispatchQueue.global(qos: .userInitiated).async {
            let p = Engine.buildPlan(options: opt, config: cfg, cancel: token, progress: { msg in
                DispatchQueue.main.async { progressText = msg }
            })
            DispatchQueue.main.async {
                L10n.current = theLang
                plan = p
                scanning = false
                progressText = token.isCancelled ? t(.uiCancelled) : t(.uiReady)
                selected = Set(p.entries.filter { $0.preselect }.map { $0.index })
                PlanStore.save(p, config: cfg)
                refreshDiskState()
            }
        }
    }

    private func doStage() {
        guard let p = plan else { return }
        working = true
        let nums = selectedEntries.map { $0.index }
        let theLang = lang
        DispatchQueue.global(qos: .userInitiated).async {
            let outcome = Engine.stage(plan: p, numbers: nums, config: cfg)
            DispatchQueue.main.async {
                L10n.current = theLang
                working = false
                selected = []
                var msg = t(.stagedResult, outcome.manifest.items.count, Fmt.bytes(outcome.manifest.totalBytes))
                if !outcome.failed.isEmpty {
                    msg += "\n" + t(.stagedFailed, outcome.failed.count)
                    msg += "\n" + outcome.failed.prefix(5).map { "· \($0.path): \($0.reason)" }.joined(separator: "\n")
                }
                resultMessage = msg
                refreshDiskState()
                runScan()   // 重新扫描，但保留横幅状态
            }
        }
    }

    private func doRelease() {
        working = true
        let theLang = lang
        DispatchQueue.global(qos: .userInitiated).async {
            let r = (try? Actions.release(manifestID: staged.manifestID, confirmed: true, config: cfg))
                ?? (count: 0, freedBytes: 0, diskDelta: 0, failed: [])
            DispatchQueue.main.async {
                L10n.current = theLang
                working = false
                resultMessage = t(.uiFreedBanner, r.count, Fmt.bytes(r.freedBytes))
                refreshDiskState()
            }
        }
    }

    private func doUndo() {
        working = true
        let theLang = lang
        DispatchQueue.global(qos: .userInitiated).async {
            let r = (try? Actions.undo(manifestID: staged.manifestID, config: cfg)) ?? (restored: 0, failed: [])
            DispatchQueue.main.async {
                L10n.current = theLang
                working = false
                resultMessage = t(.undoResult, r.restored)
                    + (r.failed.isEmpty ? "" : "\n" + t(.undoFailed, r.failed.count))
                refreshDiskState()
            }
        }
    }
}

// MARK: - 行

struct EntryRow: View {
    let entry: PlanEntry
    let lang: Lang
    let isSelected: Bool
    let onToggle: () -> Void

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Text("\(entry.index)")
                .font(.caption.monospacedDigit())
                .frame(width: 30, alignment: .trailing)
                .foregroundStyle(.secondary)

            Button(action: onToggle) {
                Image(systemName: isSelected ? "checkmark.circle.fill"
                                             : (entry.selectable ? "circle" : "circle.dashed"))
                    .font(.system(size: 18))
                    .foregroundStyle(isSelected ? Color.green
                                                : (entry.selectable ? Color.secondary : Color.gray.opacity(0.35)))
            }
            .buttonStyle(.plain)
            .disabled(!entry.selectable)
            .help(entry.selectable ? L10n.t(.uiSelectByNumber, lang) : L10n.t(.uiNotSelectable, lang))

            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 6) {
                    Text(entry.title.text(lang)).font(.body.weight(.medium))
                    riskPill
                    if !entry.selectable {
                        Text(L10n.t(.riskShowOnly, lang)).font(.caption2)
                            .padding(.horizontal, 6).padding(.vertical, 1)
                            .background(.red.opacity(0.15), in: Capsule())
                            .foregroundStyle(.red)
                    }
                }
                Text(entry.detail.text(lang)).font(.caption).foregroundStyle(.secondary)
                if let cmd = entry.officialCmd, !cmd.text(lang).isEmpty {
                    Text(L10n.t(.itemOfficialCmd, cmd.text(lang), lang: lang))
                        .font(.caption2.monospaced()).foregroundStyle(.tertiary)
                }
                Text(entry.paths.joined(separator: "   "))
                    .font(.caption2.monospaced())
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
                    .truncationMode(.middle)
                if let k = entry.keepPath {
                    Text(L10n.t(.itemKeepHint, k, lang: lang))
                        .font(.caption2).foregroundStyle(.orange)
                }
            }
            Spacer()
            VStack(alignment: .trailing, spacing: 2) {
                Text(Fmt.bytes(entry.sizeBytes)).font(.body.monospacedDigit().weight(.semibold))
                if let age = entry.ageDays, entry.kind != .cacheRule {
                    Text(Fmt.age(days: age, lang: lang)).font(.caption2).foregroundStyle(.secondary)
                }
                Text(entry.selectable ? L10n.t(.recovered, lang) : L10n.t(.uiNotSelectable, lang))
                    .font(.caption2).foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 3)
    }

    private var riskPill: some View {
        let color: Color = entry.risk == "low" ? .green : (entry.risk == "medium" ? .yellow : .red)
        let label: String
        if !entry.selectable { label = L10n.t(.riskShowOnly, lang) }
        else if entry.risk == "low" { label = L10n.t(.riskLow, lang) }
        else if entry.risk == "medium" { label = L10n.t(.riskMedium, lang) }
        else { label = L10n.t(.riskHigh, lang) }
        return Text(label)
            .font(.caption2)
            .padding(.horizontal, 6).padding(.vertical, 1)
            .background(color.opacity(0.15), in: Capsule())
            .foregroundStyle(color)
    }
}
