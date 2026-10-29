# Validation record

2026-10-30, local Apple Silicon macOS environment.

- Swift debug build and fifteen core tests pass: runtime state reduction, independent thread bindings, safe manifest/sprite bounds, partial JSONL writes/truncation, session discovery/lifecycle, runtime precedence over stale log activity, and atomic log-file replacement.
- `scripts/test-proxy.py` launches the actual monitor against a fixture executable. It checks initialization, polling, loaded-thread reads, thinking/waiting/failure/idle transitions, dead-proxy fallback, and automatic retry. This does not prove access to the real Codex socket.
- `--diagnose` loaded all eight built-in cached sprites and the user's installed custom v1 pet. It detected the current live CLI session's tool activity from its JSONL log, among 64 recent sessions.
- A temporary copy of the installed custom v2 manifest/sheet loaded as an 8×11 grid. Original user files were not modified.
- `--render-contact /tmp/harem-contact.png` rendered nine pets across nine animation rows. Visual inspection confirmed correct crop orientation and distinct state artwork.
- `scripts/package.sh` builds a release app and zip under `dist/`. Bundle Info.plist validation and strict ad-hoc code-signature verification pass.

## Still required for full completion

The tool sandbox denied access to the user's live Codex Unix socket (`Operation not permitted`). It also denied WindowServer/LaunchServices access during the desktop smoke test; the test was interrupted after it could not reach app launch. Do not claim interactive desktop behavior or real shared-daemon status syncing has been verified here.

The user has been asked to open `dist/Codex Harem.app` from Finder and report whether the three default pets appear and whether the paw menu says “Connected to shared Codex server.” After three consecutive goal turns with the same access blocker, the goal is blocked pending that report or desktop/socket access. Once desktop access is available, verify dragging, thread selection, resizing, saved positions, and live thinking/waiting/failure/completion transitions. The package documents degraded log-mode limitations explicitly.

## Final access recheck

The third goal turn again received `Operation not permitted` from the real `codex app-server proxy`. The packaged release smoke process exited with SIGABRT. Its macOS diagnostic report (`codex-harem-2026-10-30-013241.ips`) places the abort in HIServices `___RegisterApplication_block_invoke`, reached from `NSApplication.sharedApplication`, before application delegate or pet-window code. The packaged executable still runs `--help` successfully. No desktop behavior is claimed from this failed launch. No alternative desktop-control tool is available in this session.

## Per-pet walking option

Added a saved `Walk around` toggle to each pet menu. Existing layouts decode with walking disabled; new layouts persist the setting independently for each instance. Walking uses bounded horizontal routes and pauses for status changes, hover, drag, hidden windows, and Reduce Motion. Three additional passing tests cover legacy-layout migration and preference round trips, constant-speed movement and stopping, and full-window containment/edge turns on a monitor with negative coordinates. The debug build compiles the AppKit wiring. Interactive roaming still requires a desktop check outside this sandbox.

## Independent artwork and playback rate

Normal artwork loading now reads only the selected Codex Harem library, defaulting to `~/Library/Application Support/CodexHarem/Pets`. Codex artwork is accessed only by the explicit `--import-codex` command. Nine installed pets were copied into the workspace's standalone `pets/` directory; a second import kept all nine without replacing edits. Running `--diagnose --home /tmp/harem-no-codex-artwork --pets /Users/poi/Repos/codex_harem/pets` loaded all nine while the chosen Codex home had no artwork or sessions. The local release bundle includes those independent copies for one-shot first-launch initialization. Default library creation from Finder remains subject to the earlier desktop-access limitation in this environment.

The default animation rate is now 65% of the previous hard-coded rates, with saved per-pet 40%, 65%, 100%, and 125% menu options. This is a deliberate slower default, not a claim of exact built-in Codex timing parity. Gesture lifetimes and walking movement scale with playback rate. Five additional passing tests cover source-independent image imports, preserving edits, one-shot initialization/deletion, path containment, speed migration, and complete frame sequencing under time scaling.

## Native app icon

The release app now embeds `Contents/Resources/AppIcon.icns`, generated from the reference-inspired full-color master in `assets/app-icon.png`. `CFBundleIconFile` resolves to `AppIcon`. Apple ImageIO decoded all ten ICNS representations successfully (16, 32, 32, 64, 128, 256, 256, 512, 512, 1024 pixels). The delivery PNG was visually inspected, and strict bundle signature verification passes. The final app zip was regenerated. Finder's displayed icon cache has not been inspected inside this restricted desktop environment.
