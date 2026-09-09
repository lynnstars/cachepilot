# CachePilot v0.3 — Test Build Install Guide

## Install
1. Unzip `CachePilot-v0.3-test.zip` → you get `CachePilot.app`
2. Move it to your **Applications** folder
3. First launch: **right-click the app → Open** (don't double-click)
   - macOS shows "unidentified developer" — click **Open** to proceed
   - This is expected: the build is ad-hoc signed, not notarized (no paid Apple Developer account yet)
4. Still blocked? Run in Terminal: `xattr -dr com.apple.quarantine /Applications/CachePilot.app`

## What it does (v0.3)
- Scans dependency caches for AI/dev tools: npm / pnpm / yarn / pip / uv / Homebrew / cargo / go / gradle / conda + ollama / HuggingFace / Playwright / camoufox / Xcode DerivedData / editor caches
- Groups results with size, risk level, explanation, and the official CLI command
- Clean = **move to Trash (recoverable)**; low-risk items pre-checked; model/display-only items can't be one-click cleaned

## Feedback we want
- Does the scan match your machine (groups / sizes / copy)?
- Any false positives (things listed as cleanable that shouldn't be) or misses?
- Did anything break after cleaning?
