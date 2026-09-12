# CachePilot

**A macOS disk reclaimer for people who install a lot of AI/dev tooling.**

> **Status: v0.4.0 alpha** — ad-hoc signed test build, not notarized (no paid Apple Developer account yet).

Your disk fills up with **dependency caches and model residue** — npm/pip/uv/Homebrew/conda/Gradle, plus ollama models, HuggingFace downloads, Docker images, build artifacts. `CleanMyMac`-style tools don't understand package-manager semantics and won't go near conda/ollama/Docker. So the disk hits 99% and nothing can help.

CachePilot scans two things and puts them in **one numbered list you authorize**:

| | What it finds |
|---|---|
| **A · Cache rules** | npm (`_cacache`, `_npx`), pnpm store, Yarn, pip, uv, Homebrew, cargo, Go, Gradle, conda pkgs, ollama models¹, HuggingFace, ComfyUI, insightface, Playwright, camoufox, Xcode DerivedData/DeviceSupport/Archives, Docker Desktop, WeChat¹, CapCut/剪映 |
| **B · Large files & redundancy** | files above a size threshold, **identical files** (SHA-256 verified, with head/tail fast path for huge files), and **redundant versions** (`X-最新(1)`, `X-无字幕`, `report-v2-final` … clustered by name) |

¹ display-only: shown so you know where the space went, with the official command to clean it properly.

## How cleaning works (two stages — read this)

```
scan → numbered list → you pick numbers → stage  →  release
                                          │          │
                              move to Trash          permanently delete
                              (fully recoverable)    (irreversible, frees space)
```

1. **Stage** moves the selected items to the Trash. They are recoverable (`cachepilot undo`), **and the disk space is not freed yet** — CachePilot says so explicitly.
2. **Release** deletes the staged items for good and actually reclaims the space. It requires an explicit confirmation (`--confirm-irreversible` in the CLI, a red button in the GUI).
3. Every stage writes a **manifest** (`~/Library/Application Support/CachePilot/manifests/`): original path, staged path, size, timestamps. That is what `undo` uses, and it is why you can always see what was touched.

Nothing is ever deleted without you naming its number. Trash-first is not "extra safety" — it is the only reason moving 11 GB is safe to do at 90% disk usage.

## Refused by design

CachePilot refuses to act on, and never scans into:

- system paths (`/System`, `/Library`, `/Applications`, `/usr`, `/bin`, `/sbin`, `/etc`, `/var`, `/private`, `/volumes`, `/opt`)
- private data (`~/.ssh`, `~/.gnupg`, `~/Library/Keychains`, `Messages`, `Safari`, `AddressBook`)
- **the Trash folder itself** (v0.3 tried to move the Trash into the Trash — a guaranteed failure; the guard plus a regression test prevents it coming back)
- symlinks, paths outside the allowed roots, and non-existent paths
- display-only items (models, Docker image, WeChat storage)

## Install (test build)

1. Download `CachePilot-v0.4.0-test.zip` from [Releases](../../releases)
2. Unzip, move `CachePilot.app` to Applications
3. First launch: **right-click → Open** (ad-hoc signed, not notarized — Gatekeeper warns; expected)
   - Still blocked: `xattr -dr com.apple.quarantine /Applications/CachePilot.app`

## CLI

```bash
bash app/scripts/build-cli.sh          # → app/build/bin/cachepilot

cachepilot plan                        # numbered report: cache rules + large files + duplicates
cachepilot plan --mode cache --min-size 500MB --root ~/Downloads
cachepilot stage --select 1,3-5         # moves those numbers to the Trash (recoverable)
cachepilot release --confirm-irreversible   # actually frees the space
cachepilot undo                        # put the last staged batch back
cachepilot manifests                   # what was staged / released / undone
cachepilot doctor                      # language, paths, rule library, pending staged bytes
```

`--select` numbers refer to the plan that was just printed (saved to `plans/latest.json`); plans older than 60 minutes are refused, so numbering can never be stale.

## Language

The interface follows the **system language**: any `zh*` language → Chinese; **every other language → English**. Override with `--lang zh|en` (CLI) or `CACHEPILOT_LANG` (both), or the globe menu in the GUI. Rule text is bilingual inside the rule library itself (`{"en": …, "zh": …}`).

## Rule library

`rules/cleanable_rules.json` (schema v2) is the single source of truth — bilingual strings, risk level, paths, `min_size_mb`, why-it's-safe, official command, `default_clean` / `show_only`.

```json
{
  "id": "my-tool-cache",
  "category": "package-manager",
  "tool": "my-tool",
  "name": { "en": "my-tool download cache", "zh": "my-tool 下载缓存" },
  "risk": "low",
  "paths": ["~/.my-tool/cache"],
  "min_size_mb": 50,
  "why": { "en": "re-downloaded on next use", "zh": "下次使用时重新下载" },
  "official_cmd": { "en": "my-tool cache clean", "zh": "my-tool cache clean" },
  "default_clean": true
}
```

Load order: app bundle → `CACHEPILOT_RULES` → next to the binary → `~/Library/Application Support/CachePilot/rules/` (hot-swap rules without rebuilding) → repo `rules/` in development.

## Development

Requirements: macOS 14+, Xcode **Command Line Tools** only (no full Xcode — `swiftc` + the SDK builds the SwiftUI app).

```bash
bash app/scripts/make-app.sh      # build CachePilot.app (ad-hoc signed, sealed Info.plist)
bash app/scripts/build-cli.sh     # build the cachepilot CLI (same engine)
bash scripts/run-tests.sh         # Swift unit tests + CLI end-to-end + Python tests
```

```
app/Sources/CachePilot/   core: L10n, Models, Finder (scanner/detectors), Actions, Engine, CLI
app/Sources/CachePilot/   GUI: CachePilotApp.swift, ContentView.swift
app/Sources/CLI/          CLI entry point (shares the core)
app/Tests/                Swift test suite
app/scripts/              build scripts
rules/                    bilingual rule library (schema v2)
scanner/scan.py           legacy read-only preview (still works, cannot clean anything)
scripts/run-tests.sh      full test suite
.github/workflows/        CI (tests on push) + release workflow (build + attach zip on tag)
```

The Swift core is the single engine: the app and the CLI call exactly the same code, so what you test in CI is what you run.

## Roadmap (not done yet — no silent promises)

- [ ] Developer ID signing + notarization (official distribution)
- [ ] App icon
- [ ] node_modules / venv inventory (directory-level scan; today only large individual files are listed)
- [ ] Docker prune integration (`docker system prune` invocation + shrink the disk image) — currently display-only
- [ ] Rule cloud updates (Pro) / scheduled background scans
- [ ] Mac App Store evaluation (sandboxing limits arbitrary cache access)

## License

Not chosen yet — all rights reserved until further notice.
