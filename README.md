# CachePilot

**A macOS disk cleaner built for AI engineers & tinkerers.**

> **Status: v0.3 alpha** — ad-hoc signed test build. Not notarized yet (no paid Apple Developer account). Works, but expect rough edges.

The problem: if you install AI tooling and dependencies from the terminal — `npm`, `pip`, `uv`, Homebrew, `conda`, `cargo`, Docker, `ollama`, HuggingFace models, Xcode — your disk fills up with **dependency caches and model residue**, not app caches. Classic cleaners (CleanMyMac-style, "app cache" mindset) don't understand package-manager semantics and are afraid to touch conda/ollama/Docker. So your disk hits 99% and the "cleaners" can't help.

CachePilot scans exactly what AI engineers accumulate, groups it by tool, shows you size / risk / *why it's safe to delete*, and cleans by **moving items to the Trash (recoverable)** — never a hard `rm`.

## Features (v0.3)

- 🔍 Scans dependency caches and AI residue by tool:
  | Category | Tools |
  |---|---|
  | Package managers | npm, pnpm, yarn, pip, uv, Homebrew, cargo, go, gradle, conda pkg cache |
  | AI tools | ollama models (display-only), HuggingFace hub cache, ComfyUI temp |
  | Browser automation | Playwright, camoufox browser engines |
  | Build artifacts | Xcode DerivedData |
  | App caches (whitelist) | 剪映/CapCut-style editor caches |
- 🎯 Every item shows: **size, risk level, why it's safe to delete, and the official CLI command** that does the same
- 🗑️ Cleaning = **move to Trash** (recoverable), never permanent delete
- 🚦 Risk model: 🟢 low-risk pre-checked · 🟡 medium opt-in · 🔴 high/`show-only` items (e.g. large local models, node_modules inventory) are **never** one-click deletable
- ⚙️ Rule-driven: `rules/cleanable_rules.json` defines everything — easy to audit, easy to extend

## Why trust it?

1. **Cache-only, whitelisted paths** — it never touches documents, chat history, project source, or model files (models are displayed, not auto-deleted)
2. **Trash, not `rm`** — everything it cleans can be restored from the Trash
3. **Transparent** — every item explains *what it is, why it's safe, and the official command*
4. **No telemetry, no network calls** — the app scans locally and does nothing else

## Install (test build)

1. Download `CachePilot-v0.3-test.zip` from [Releases](../../releases)
2. Unzip, move `CachePilot.app` to Applications
3. First launch: **right-click → Open** (it's ad-hoc signed, not notarized — Gatekeeper will warn; that's expected until we get a Developer ID cert)
   - If blocked: `xattr -dr com.apple.quarantine /Applications/CachePilot.app`

## Usage

1. Click **Scan** — reads the rule library and measures real sizes on your machine (read-only)
2. Review grouped results (category → item → size / risk / reason / official command)
3. Check what you want (green = pre-checked)
4. Click **Move to Trash (recoverable)** → confirm → done. Space updates live.

## Development

Requirements: macOS 14+, Xcode **Command Line Tools** only (no full Xcode needed — `swiftc` + bundled SDK compiles the SwiftUI app).

```bash
# Build the .app bundle
app/scripts/make-app.sh

# CLI scanner (same logic, Python)
python3 scanner/scan.py          # read-only preview
python3 scanner/scan.py --json   # machine-readable
```

```
app/                    # SwiftUI app source (no Xcode project — swiftc based)
rules/cleanable_rules.json      # rule library (single source of truth)
scanner/scan.py                 # CLI scanner
prototype/                      # HTML interaction prototype & clean lists
TEST_CASES.md                   # test cases
```

## Extending the rule library

Add an entry to `rules/cleanable_rules.json`:

```json
{
  "id": "my-tool-cache",
  "category": "package-manager",
  "tool": "my-tool",
  "name": "my-tool download cache",
  "risk": "low",
  "paths": ["~/.my-tool/cache"],
  "min_size_mb": 50,
  "why": "Cache of downloaded packages; re-downloaded on next use",
  "official_cmd": "my-tool cache clean",
  "default_clean": true
}
```

Categories: `package-manager` · `ai-tools` · `browser-automation` · `build-artifacts` · `app-caches` · `general`

## Roadmap

- [x] Rule library v1 + read-only scanner
- [x] SwiftUI app: scan → group → check → move to Trash
- [x] Ad-hoc test distribution
- [ ] Developer ID signing + notarization (official distribution)
- [ ] GitHub Actions CI (build on tag)
- [ ] Rule cloud updates (Pro) / scheduled scans
- [ ] Mac App Store (sandbox-limited) evaluation

## Disclaimer

This tool deletes/moves files based on its rule library. It's designed to be conservative (Trash-first, display-only for models), but **always review scan results before cleaning** — you are responsible for your own machine. Test builds are unsigned/not notarized; install at your own risk.

License: not yet chosen — all rights reserved until further notice.
