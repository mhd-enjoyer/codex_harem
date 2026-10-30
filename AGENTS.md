# AGENTS.md

Swift 6 package (language mode v5), macOS 13+, no third-party dependencies. Two targets: `PetCore` (pure logic library, all tests) and `CodexHarem` (AppKit executable + CLI in `Sources/CodexHarem/main.swift`).

## Commands

```sh
swift run codex-harem            # run the app
swift test                       # PetCore tests only; AppKit executable is untested
swift build && python3 scripts/test-proxy.py   # transport fixture; needs the debug build first
./scripts/package.sh             # release app + zip under dist/
```

Headless verification (no UI): `.build/debug/codex-harem --diagnose`, `--render-contact /tmp/pets.png`, `--demo`, `--probe N`.

Sandboxed environments: `swift build`/`swift test` need `CLANG_MODULE_CACHE_PATH` and `SWIFTPM_MODULECACHE_OVERRIDE` pointed at a writable dir plus `--disable-sandbox` (see README "Verification"). `scripts/package.sh` does this already and also uses `-debug-info-format none` to skip a sandbox-breaking dSYM step.

## Desktop-testing limit

Launching the real app (or `--smoke`) requires WindowServer access. From a sandbox it SIGABRTs in `NSApplication.sharedApplication` before any app code runs. Don't claim interactive desktop behavior is verified; rely on the headless modes above. `VALIDATION.md` is the running record of what was actually verified vs. blocked.

## Architecture rules

- Put testable logic in `PetCore` (status reduction, manifest validation, JSONL tailing, harness monitors, walking math). `CodexHarem` is AppKit wiring only; keep logic out of it so `swift test` can cover it.
- Artwork loads exclusively from the independent library `~/Library/Application Support/CodexHarem/Pets/*/pet.json` (override `--pets`); layout is the sibling `pets.json`. Never read Codex's artwork cache outside the explicit one-shot `--import-codex` path.
- Thread IDs are namespaced per provider (`claude:<uuid>`, `opencode:<ses>`); Codex IDs are unprefixed. Keep this scheme so saved bindings survive.
- Sprite sheets: v1 is 8 columns × 9 rows; v2 adds 2 rows of clockwise look directions starting at up. Animation overrides use zero-based row-major frame indices. Default playback is 65% of authored fps; gestures and walking scale with it.

## Known degraded modes (documented, don't "fix")

- Claude Code: transcript tailing cannot expose permission prompts → waiting state never appears.
- opencode 2.x: when attached to the registered `opencode serve --service`, its `/api/session/active` map and `/api/event` stream cover TUI-run sessions. When forced to spawn its own server instead, those channels only cover that server's sessions; busy state for TUI-run sessions is recovered from `~/.local/share/opencode/opencode.db` read-only (`OpenCodeActivity` in PetCore), where a turn is active until its newest assistant message gains `finish`/`time.completed`, decaying after 15 min. The 2.x service can hold its WAL exclusively, so those reads may stop at the last checkpoint. Permission requests are not persisted → waiting depends on the SSE stream.
- Codex JSONL fallback (no shared server): cannot reliably show pending approvals or a killed process; retry every 10s.

The `pets/` directory is gitignored local artwork that `package.sh` optionally bundles as first-launch seeds; a zip built here embeds those images.
