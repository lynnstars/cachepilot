import Foundation

// MARK: - CachePilot 自动化测试（无 XCTest 依赖，swiftc 直接编译运行）
// 覆盖：语言解析 / 规则库 schema / 安全护栏 / 重复检测 / 冗余版本 / 大文件遍历 /
//       暂存-撤销-释放三步 / 清单编号与落盘 / 报告渲染

var passed = 0
var failed = 0
var failures: [String] = []

func section(_ s: String) { print("\n── \(s) ──") }

func check(_ cond: Bool, _ name: String, _ detail: String = "") {
    if cond {
        passed += 1
        print("  ✓ \(name)")
    } else {
        failed += 1
        failures.append("\(name) \(detail)")
        print("  ✗ \(name) \(detail.isEmpty ? "" : "→ " + detail)")
    }
}

func eq<T: Equatable>(_ a: T, _ b: T, _ name: String) {
    check(a == b, name, "got \(a), want \(b)")
}

// MARK: 沙箱

// 注意：沙箱必须放在用户 home 下 —— /var/folders(TMPDIR) 命中系统黑名单，
// 会被 BigFinder/SafetyConfig 正确拒绝，测试无法在此构造场景。
let sandbox = URL(fileURLWithPath: NSHomeDirectory())
    .appendingPathComponent("Library/Caches/CachePilotTests-\(UUID().uuidString)")
try! FileManager.default.createDirectory(at: sandbox, withIntermediateDirectories: true)
defer { try? FileManager.default.removeItem(at: sandbox) }

func makeFile(_ rel: String, bytes: Int, seed: UInt8 = 1, mtime: Date? = nil) -> String {
    let url = sandbox.appendingPathComponent(rel)
    try? FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
    var data = Data(count: bytes)
    if seed != 0 {
        for i in stride(from: 0, to: bytes, by: 4096) { data[i] = seed &+ UInt8((i / 4096) % 251) }
    }
    try? data.write(to: url)
    if let m = mtime {
        try? FileManager.default.setAttributes([.modificationDate: m], ofItemAtPath: url.path)
    }
    return url.standardized.path
}

let cfg = SafetyConfig(allowedRoots: [sandbox.path],
                       trashDir: sandbox.appendingPathComponent(".Trash").path,
                       dataDir: sandbox.appendingPathComponent("data").path)

// MARK: 1. 语言解析（zh → 中文；其他一切语言 → 英文）

section("1. Language resolution (system language → zh, everything else → en)")
eq(L10n.resolve(preferred: ["zh-Hans-CN"], env: nil), Lang.zh, "zh-Hans-CN → zh")
eq(L10n.resolve(preferred: ["zh-Hant-TW"], env: nil), Lang.zh, "zh-Hant-TW → zh")
eq(L10n.resolve(preferred: ["zh"], env: nil), Lang.zh, "zh → zh")
eq(L10n.resolve(preferred: ["en-US"], env: nil), Lang.en, "en-US → en")
eq(L10n.resolve(preferred: ["ja-JP"], env: nil), Lang.en, "ja-JP → en (unsupported → English)")
eq(L10n.resolve(preferred: ["de-DE", "fr-FR"], env: nil), Lang.en, "de/fr → en")
eq(L10n.resolve(preferred: ["ja-JP", "en-GB"], env: nil), Lang.en, "ja then en → en")
eq(L10n.resolve(preferred: ["en-US"], env: "zh"), Lang.zh, "CACHEPILOT_LANG=zh overrides system")
eq(L10n.resolve(preferred: ["zh-Hans"], env: "en"), Lang.en, "CACHEPILOT_LANG=en overrides system")
eq(L10n.resolve(preferred: ["zh-Hans"], env: "fr"), Lang.en, "env unsupported (fr) → en")
eq(L10n.resolve(preferred: [], env: nil), Lang.en, "no preferred languages → en")

check(L10n.missingZhKeys.isEmpty, "every string key has a Chinese translation",
      "missing: \(L10n.missingZhKeys.map { $0.rawValue })")
check(L10n.t(.riskLow, .zh) != L10n.t(.riskLow, .en), "zh and en tables differ")
check(L10n.t(.sectionBig, .zh).contains("大文件"), "zh section title is Chinese")

section("1b. Size parsing/formatting")
eq(Fmt.parseSizeMB("200MB"), 200.0, "parse 200MB")
eq(Fmt.parseSizeMB("1.5GB"), 1536.0, "parse 1.5GB")
eq(Fmt.parseSizeMB("500"), 500.0, "parse bare number as MB")
check(Fmt.parseSizeMB("nope") == nil, "parse garbage → nil")
eq(Fmt.bytes(1_073_741_824), "1.0 GB", "format 1 GiB")
eq(Fmt.bytes(2_147_483_648), "2.0 GB", "format 2 GiB")

// MARK: 2. 规则库 schema v2 + v0.3 已知错误回归

section("2. Rule library (schema v2, bilingual, v0.3 data bugs fixed)")
let repoRules = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
    .deletingLastPathComponent()
    .appendingPathComponent("rules/cleanable_rules.json")
let rulesURL = FileManager.default.fileExists(atPath: repoRules.path)
    ? repoRules
    : URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
        .appendingPathComponent("rules/cleanable_rules.json")

if let rf = try? RuleScanner.loadRules(at: rulesURL) {
    eq(rf.schemaVersion, 2, "schema_version == 2")
    check(rf.rules.count >= 18, "rule count >= 18", "got \(rf.rules.count)")
    let missingZh = rf.rules.filter { !$0.name.hasZh || !$0.why.hasZh }
    check(missingZh.isEmpty, "every rule has zh name+why", "missing: \(missingZh.map { $0.id })")
    let badCat = rf.categories.filter { !$0.value.hasZh }
    check(badCat.isEmpty, "every category has zh text", "missing: \(badCat.keys)")
    let badRisk = rf.rules.filter { !["low", "medium", "high"].contains($0.risk) }
    check(badRisk.isEmpty, "risk values valid", "bad: \(badRisk.map { $0.id })")
    let noPath = rf.rules.filter { $0.paths.isEmpty }
    check(noPath.isEmpty, "every rule has at least one path", "empty: \(noPath.map { $0.id })")
    let badShowOnly = rf.rules.filter { $0.isShowOnly && $0.isDefaultClean }
    check(badShowOnly.isEmpty, "display-only rules are never default-cleaned",
          "bad: \(badShowOnly.map { $0.id })")

    // v0.3 的三个具体数据错误必须保持修好（回归测试）
    let trashRules = rf.rules.filter { r in r.paths.contains { $0.contains("/.Trash") || $0.hasSuffix(".Trash") } }
    check(trashRules.isEmpty, "no rule points at ~/.Trash (v0.3 moved Trash into itself)",
          "found: \(trashRules.map { $0.id })")
    let pnpm = rf.rules.first { $0.id == "pnpm-store" }
    check(pnpm?.paths.contains("~/Library/pnpm/store") == true,
          "pnpm rule points at the real macOS store (~/Library/pnpm/store)")
    let npm = rf.rules.first { $0.id == "npm-cacache" }
    check(npm?.paths.contains("~/.npm/_npx") == true, "npm rule covers _npx (largest npm cache)")
    check(rf.rules.contains { $0.id == "conda-pkgs" }, "conda packaged as a real rule (README claim was false in v0.3)")
    check(rf.rules.contains { $0.id == "docker-desktop" && $0.isShowOnly },
          "Docker is present but display-only (file move would break it)")
} else {
    check(false, "load rules from \(rulesURL.path)")
}

// MARK: 3. 安全护栏

section("3. Safety guards")
let ok = makeFile("work/file.txt", bytes: 1024)
check((try? cfg.validate(ok)) != nil, "inside allowed root → allowed")
check((try? cfg.validate(cfg.trashDir)) == nil, "trash dir itself → refused")
check((try? cfg.validate(sandbox.path)) == nil, "ancestor of trash dir → refused")
check((try? cfg.validate("/System/Library/Caches")) == nil, "system path → refused")
check((try? cfg.validate("/Applications/Safari.app")) == nil, "Applications → refused")
check((try? cfg.validate(NSHomeDirectory() + "/.ssh/id_rsa")) == nil, "~/.ssh → refused")
check((try? cfg.validate(NSHomeDirectory() + "/Documents/nope-\(UUID().uuidString)")) == nil,
      "outside allowed roots → refused")
check((try? cfg.validate(sandbox.appendingPathComponent("data/manifests/x.json").path)) == nil,
      "CachePilot's own data dir → refused")
check((try? cfg.validate(sandbox.appendingPathComponent("missing-\(UUID().uuidString)").path)) == nil,
      "non-existent → refused")

let linkPath = sandbox.appendingPathComponent("work/link.txt").path
try? FileManager.default.createSymbolicLink(atPath: linkPath, withDestinationPath: ok)
check((try? cfg.validate(linkPath)) == nil, "symlink → refused")

// MARK: 4. 重复文件检测

section("4. Duplicate detection")
let d = sandbox.appendingPathComponent("dups").path
let old = Date().addingTimeInterval(-86_400 * 30)
let f1 = makeFile("dups/a.bin", bytes: 400_000, seed: 7, mtime: old)          // 原始（最早）
let f2 = makeFile("dups/a-copy.bin", bytes: 400_000, seed: 7, mtime: Date()) // 同内容
let f3 = makeFile("dups/different.bin", bytes: 400_000, seed: 9)             // 同大小不同内容
let f4 = makeFile("dups/tiny.bin", bytes: 1024, seed: 3)                     // 低于阈值

let dups = BigFinder.duplicates(files: BigFinder.walk(roots: [d], minBytes: 1024).files,
                                minBytes: 1024)
check(dups.count == 1, "exactly one duplicate group", "got \(dups.count)")
if let g = dups.first {
    eq(g.files.count, 2, "group has 2 members")
    eq(g.confidence, Confidence.exact, "full-hash verified → exact")
    eq(g.keepPath, f1, "keeps the oldest copy")
    check(g.files.contains { $0.path == f2 }, "copy is in the group")
    check(!g.files.contains { $0.path == f3 }, "same-size different content is NOT grouped")
    check(!g.files.contains { $0.path == f4 }, "below threshold is not grouped")
}

let likely = BigFinder.duplicates(files: BigFinder.walk(roots: [d], minBytes: 1024).files,
                                  minBytes: 1024, exactVerifyLimit: 1)
check(likely.first?.confidence == Confidence.likely, "huge files fall back to head/tail → likely")

// MARK: 5. 冗余版本（名称启发式，老板的真实场景）

section("5. Redundant versions")
let v = sandbox.appendingPathComponent("videos").path
_ = makeFile("videos/AI大赛视频-最新(1).mp4", bytes: 300_000, seed: 11, mtime: old)
_ = makeFile("videos/AI大赛视频-最新(1)(1).mp4", bytes: 310_000, seed: 12)
_ = makeFile("videos/AI大赛视频-无字幕.mp4", bytes: 320_000, seed: 13, mtime: Date())
_ = makeFile("videos/另一个视频.mp4", bytes: 330_000, seed: 14)
let vFiles = BigFinder.walk(roots: [v], minBytes: 1024).files
let versions = BigFinder.redundantVersions(files: vFiles, minGroupBytes: 1024)
eq(versions.count, 1, "one redundant-version group")
if let g = versions.first {
    eq(g.files.count, 3, "all three near-identical names grouped")
    eq(g.confidence, Confidence.suspect, "name heuristic → suspect (never auto-selected)")
}
eq(BigFinder.normalizeName("AI大赛视频-最新(1).mp4"), BigFinder.normalizeName("AI大赛视频-无字幕.mp4"),
   "name normalisation strips (1)/最新/无字幕")
eq(BigFinder.normalizeName("report-v2-final.pdf"), BigFinder.normalizeName("report.pdf"),
   "name normalisation strips version/final")

// MARK: 6. 大文件遍历

section("6. Large-file walk")
let b = sandbox.appendingPathComponent("big").path
let small = makeFile("big/small.bin", bytes: 100_000)
let mid = makeFile("big/mid.bin", bytes: 2_000_000)
let big = makeFile("big/大文件.mov", bytes: 5_000_000)
_ = makeFile("big/.ssh/big.bin", bytes: 5_000_000)
try? FileManager.default.createSymbolicLink(atPath: sandbox.appendingPathComponent("big/linkout.mov").path,
                                            withDestinationPath: big)
let walked = BigFinder.walk(roots: [b], minBytes: 1_000_000)
let paths = walked.files.map { $0.path }
check(paths.count == 2, "only files ≥ threshold are listed", "got \(paths.count)")
check(paths.contains(mid) && paths.contains(big), "mid + big listed")
check(!paths.contains(small), "small file excluded")
check(!paths.contains(where: { $0.contains("/.ssh/") }), "blocked dir (.ssh) is skipped")
check(!paths.contains(where: { $0.hasSuffix("/linkout.mov") }), "symlinks are not followed")
eq(walked.files.first?.kind, FileKind.video, ".mov classified as video")
check(walked.files.count >= 2, "walk returned files at all", "got \(walked.files.count)")
check((walked.files.first?.bytes ?? 0) >= (walked.files.last?.bytes ?? 0), "sorted by size desc")
check(BigFinder.isBlocked("/System/Library/CoreServices"), "/System is blocked")
check(!BigFinder.isBlocked(sandbox.path + "/ok"), "sandbox path not blocked")

// MARK: 7. 暂存 → 撤销 → 彻底释放

section("7. Stage → undo → release")
let target = makeFile("work/to-clean.bin", bytes: 200_000)
let outcome = Actions.stage(targets: [(target, 200_000, "test")], planID: "plan-1", config: cfg)
eq(outcome.manifest.items.count, 1, "one item staged")
eq(outcome.failed.count, 0, "no failures")
check(!FileManager.default.fileExists(atPath: target), "original path is gone")
check(outcome.manifest.items[0].stagedPath.hasPrefix(cfg.trashDir + "/"), "staged inside the Trash")
check(FileManager.default.fileExists(atPath: outcome.manifest.items[0].stagedPath), "staged file exists")
check(Actions.stagedBytes(config: cfg).bytes == 200_000, "stagedBytes reports the pending size")
check(Actions.manifests(config: cfg).count == 1, "manifest persisted")
eq(Actions.stagedBytes(config: cfg).manifestID, outcome.manifest.id, "latest staged manifest id")

let undo = try! Actions.undo(manifestID: outcome.manifest.id, config: cfg)
eq(undo.restored, 1, "undo restored the file")
check(FileManager.default.fileExists(atPath: target), "file is back at its original path")
eq(Actions.manifests(config: cfg).first { $0.id == outcome.manifest.id }?.state,
   ManifestState.undone, "manifest marked undone")

// 再暂存一次，走「彻底释放」
let target2 = makeFile("work/to-release.bin", bytes: 300_000)
let staged2 = Actions.stage(targets: [(target2, 300_000, "test2")], planID: "plan-2", config: cfg)
do {
    _ = try Actions.release(manifestID: staged2.manifest.id, confirmed: false, config: cfg)
    check(false, "release without confirmation must throw")
} catch {
    check((error as? SafetyError) == SafetyError.confirmRequired, "release without --confirm-irreversible refused")
}
let rel = try! Actions.release(manifestID: staged2.manifest.id, confirmed: true, config: cfg)
eq(rel.count, 1, "one item released")
check(rel.freedBytes >= 300_000, "freed bytes measured (>= file size)", "got \(rel.freedBytes)")
check(!FileManager.default.fileExists(atPath: staged2.manifest.items[0].stagedPath), "staged file removed")
eq(Actions.manifests(config: cfg).first { $0.id == staged2.manifest.id }?.state,
   ManifestState.released, "manifest marked released")
check(Actions.stagedBytes(config: cfg).count == 0, "nothing left staged")

// 拒绝：不在允许根内的路径不进入清单
let outside = "/Applications/not-allowed-\(UUID().uuidString)"
let bad = Actions.stage(targets: [(outside, 1, "x")], planID: "p3", config: cfg)
eq(bad.manifest.items.count, 0, "path outside allowed roots is not staged")
eq(bad.failed.count, 1, "and it is reported as a refusal")

// 拒绝：撤销/释放只作用于我们自己暂存进废纸篓的东西
let fake = Manifest(id: "fake", planID: "p", createdAt: Date(), state: .staged,
                    items: [StagedItem(originalPath: sandbox.appendingPathComponent("work/file.txt").path,
                                       stagedPath: sandbox.appendingPathComponent("not-in-trash.json").path,
                                       sizeBytes: 1, label: "x")],
                    releasedCount: nil, releasedBytes: nil, undoneCount: nil, note: nil)
Actions.saveManifest(fake, config: cfg)
let fakeRel = try! Actions.release(manifestID: "fake", confirmed: true, config: cfg)
eq(fakeRel.count, 0, "release ignores items not staged by us")
eq(fakeRel.failed.count, 1, "and reports them as refused")

// MARK: 8. 清单：编号稳定 + 落盘 + 过期保护

section("8. Plan numbering, persistence, staleness")
let scanRoot = sandbox.appendingPathComponent("scanroot").path
_ = makeFile("scanroot/cache/blob.bin", bytes: 2_000_000, seed: 21)
_ = makeFile("scanroot/movies/电影.mkv", bytes: 3_000_000, seed: 22)
_ = makeFile("scanroot/movies/电影-最新(1).mkv", bytes: 4_000_000, seed: 23)

// 注入一份只指向沙箱的测试规则库
let testRules: [String: Any] = [
    "schema_version": 2,
    "categories": ["package-manager": ["en": "Package manager caches", "zh": "包管理器缓存"]],
    "rules": [[
        "id": "test-cache", "category": "package-manager", "tool": "test",
        "name": ["en": "Test cache", "zh": "测试缓存"],
        "risk": "low", "paths": [scanRoot + "/cache"], "min_size_mb": 1,
        "why": ["en": "safe", "zh": "安全"],
        "official_cmd": ["en": "rm -rf", "zh": "rm -rf"],
        "default_clean": true,
    ]],
]
let rulesPath = sandbox.appendingPathComponent("test-rules.json").path
try! JSONSerialization.data(withJSONObject: testRules).write(to: URL(fileURLWithPath: rulesPath))
setenv("CACHEPILOT_RULES", rulesPath, 1)
defer { unsetenv("CACHEPILOT_RULES") }

var opt = ScanOptions()
opt.mode = .all
opt.minSizeMB = 1
opt.dupMinSizeMB = 1
opt.versionMinGroupMB = 1
opt.roots = [scanRoot]
opt.maxWalkSeconds = 30
let plan = Engine.buildPlan(options: opt, config: cfg)
check(plan.entries.count >= 3, "plan has cache + big + version entries", "got \(plan.entries.count)")
eq(plan.entries.map { $0.index }, Array(1...plan.entries.count), "entries numbered 1..N in order")
eq(plan.entries.first?.kind, EntryKind.cacheRule, "cache rules come first")
check(plan.entries.first?.preselect == true, "low-risk default_clean rule is pre-selected")
check(plan.entries.filter { $0.kind == .bigFile || $0.kind == .duplicate || $0.kind == .redundantVersion }
        .allSatisfy { !$0.preselect }, "large files / duplicates / versions are never pre-selected")
check(plan.entries.allSatisfy { !$0.paths.isEmpty }, "every entry shows the paths it would move")
check(plan.totalSelectableBytes > 0, "selectable total computed")
let dupOrVersion = plan.entries.first { $0.kind == .duplicate || $0.kind == .redundantVersion }
check(dupOrVersion?.keepPath != nil, "duplicate/version entries state which copy is kept")

PlanStore.save(plan, config: cfg)
let loaded = try? PlanStore.latest(config: cfg)
eq(loaded?.id, plan.id, "plan round-trips through the store")
eq(loaded?.entries.count, plan.entries.count, "entry count survives round-trip")

// 过期清单必须拒绝（编号授权的前提）
var stale = plan
stale = Plan(id: "stale", createdAt: Date().addingTimeInterval(-7200), lang: .en,
             mode: "all", minSizeMB: 1, roots: [scanRoot], entries: plan.entries,
             scannedAt: Date(), diskTotalBytes: 1, diskFreeBytes: 1)
PlanStore.save(stale, config: cfg)
do {
    _ = try PlanStore.latest(config: cfg, maxAgeMinutes: 60)
    check(false, "stale plan must be refused")
} catch let e as SafetyError {
    if case .stalePlan = e { check(true, "stale plan refused (age reported)") }
    else { check(false, "stale plan refused", "\(e)") }
} catch { check(false, "stale plan refused", "\(error)") }

// MARK: 9. 报告渲染（中英双语）

section("9. Localized report rendering")
L10n.current = .en
let en = Engine.renderText(plan: plan, lang: .en)
L10n.current = .zh
let zh = Engine.renderText(plan: plan, lang: .zh)
check(en.contains("[  1]"), "report numbers entries")
check(en.contains(L10n.t(.sectionCache, .en)), "english report has english section title")
check(zh.contains("缓存与依赖规则"), "chinese report has chinese section title")
check(en != zh, "the two renderings differ")
check(en.contains(scanRoot), "report shows real paths")

// MARK: 10. 引擎端到端：按编号暂存

section("10. Authorize-by-number end to end")
let cacheTarget = scanRoot + "/cache/blob.bin"
let plan2 = Engine.buildPlan(options: opt, config: cfg)
let idx = plan2.entries.first { $0.kind == .cacheRule }!.index
let staged3 = Engine.stage(plan: plan2, numbers: [idx], config: cfg)
eq(staged3.manifest.items.count, 1, "selected entry staged exactly one path")
check(!FileManager.default.fileExists(atPath: scanRoot + "/cache"),
      "the cache rule's directory was moved as a whole")
check(FileManager.default.fileExists(atPath: staged3.manifest.items[0].stagedPath), "and it is in the Trash")
_ = try? Actions.undo(manifestID: staged3.manifest.id, config: cfg)
check(FileManager.default.fileExists(atPath: scanRoot + "/cache"), "undo brought the directory back")

// MARK: 汇总

print("\n" + String(repeating: "=", count: 60))
print("CachePilot tests: \(passed) passed, \(failed) failed")
if !failures.isEmpty {
    print("\nFailures:")
    for f in failures { print("  ✗ \(f)") }
}
print(String(repeating: "=", count: 60))
exit(failed == 0 ? 0 : 1)
