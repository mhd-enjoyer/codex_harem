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

## Agent harnesses: Claude Code and opencode

Each pet can now choose which harness it listens to (all, Codex, Claude Code, opencode) from a `Listen to` submenu; the choice persists in `pets.json` and legacy layouts decode with `all`. Thread IDs are namespaced (`claude:<uuid>`, `opencode:<ses>`); Codex IDs stay unprefixed so existing bindings keep resolving.

- Claude Code: `ClaudeMonitor` tails `~/.claude/projects/**/*.jsonl` with the existing bounded tail reader. The reducer was verified against the user's real transcripts (63 sessions): `assistant` records with `tool_use` map to working, text/thinking records to thinking, `user` `tool_result` to thinking, `system/turn_duration` to completed, and `ai-title` supplies thread names with a `cwd · id` fallback. `--diagnose` printed plausible per-session statuses (6 completed, 1 idle, 3 thinking). Waiting/approval and interruption states are not observable from transcripts; that degraded limitation is documented in the README.
- opencode: `OpenCodeWatcher` spawns `opencode serve --hostname 127.0.0.1 --port <free>` (ephemeral port discovered via a bind(0) probe), polls `/session` and `/session/status` once per second, and consumes the `/event` SSE stream for `permission.asked` (waiting), `permission.replied`, `session.idle`, and `session.error` (aborted → interrupted, otherwise failed). Schemas were verified against a live `opencode serve` 1.19.5 instance and its OpenAPI spec before implementation. `--probe 14` merged real threads from all three providers in one snapshot, including this workspace's actual opencode session. Basic auth honors `OPENCODE_SERVER_PASSWORD`; HTTP clients bypass system proxies.
- Nine new passing tests cover harness filtering in `Selection`, transcript reducer mapping and monitor tailing (including partial writes), opencode status/event mapping and completion transitions, and legacy-layout harness migration. Interactive desktop behavior remains subject to the sandbox limitation recorded above.

## opencode busy state from shared storage

A pet set to "Listen to → opencode" stayed idle because opencode 1.19.5's `/session/status` map and `/event` stream only cover sessions owned by the spawned server process; a session busy in the user's TUI is invisible to both. Verified live: repeated curls returned `{}` while this session was actively running, and a 12-second SSE listen captured only `server.connected`/`heartbeat`. Cross-process activity is persisted in `~/.local/share/opencode/opencode.db` (tables `part`, `message`, `event`) with suffixed event types (`message.part.updated.1`, etc.) the SSE reducer never sees, and no `permission.*` rows.

`OpenCodeActivity` (PetCore) now opens that database read-only once per second. A turn is active while the newest message lacks `finish`/`time.completed` (verified: in-flight assistant messages have neither; finished ones carry both, e.g. `finish: "tool-calls"`), or while a recent user prompt is unanswered. The newest part type maps `tool` → working, anything else → thinking; evidence older than 15 minutes decays to idle, matching the Claude transcript decay. The watcher folds this over its existing poll/SSE/waiting logic. Four tests cover the mapping and an end-to-end temp-database poll; all 29 pass. `--probe` printed `opencode:thinking:Create AGENTS.md for codex_har` for this live session, and `--diagnose` reports `shared storage present`.

Still unrecoverable from storage: permission requests (`waiting`) for TUI-run sessions — no `pending` tool state is ever persisted. The README's opencode section documents this. Separately observed: `opencode serve` children survive the watcher's `Process.terminate()` (two orphans from earlier runs kept listening); not addressed here.


## opencode 2.x API compatibility

The integration above targeted opencode 1.19.5. The installed CLI is now 2.2.1, which moved the HTTP API to `/api/*`, requires Basic auth with a server-generated password (published in `~/.local/state/opencode/service.json`), wraps list responses in `{ "data": ... }`, exposes live work through `/api/session/active`, and sends SSE fields under `data` instead of `properties`. The watcher previously called `/session`, `/session/status`, and `/event`, so every request missed: the old paths return the web UI or 404, the session list stayed empty, and the pet never left idle. The 2.x service also holds its SQLite WAL exclusively, so the read-only `OpenCodeActivity` fallback only sees the last checkpoint and must not be treated as live evidence while attached.

`OpenCodeWatcher` now attaches to the registered shared service when it answers `/api/session`, otherwise spawns `opencode serve` with a generated `OPENCODE_SERVER_PASSWORD`. It polls `/api/session` and `/api/session/active`, consumes `/api/event`, and still detects 1.x servers through the older routes. `OpenCodeReducer` maps `session.execution.started/succeeded/failed/interrupted`, `session.step.started`, `session.retry.scheduled`, `session.tool.called/success/failed`, and the existing permission events, accepting either the `data` or `properties` envelope.

Verified live against the running 2.2.1 service on 127.0.0.1:11451: `--probe 6` printed `opencode · shared service on 127.0.0.1:11451`, reported this actively running session as `opencode:thinking:Greeting`, and left completed sessions idle. `--diagnose` reports the registered service path. `swift test` passes all 30 PetCore tests, including the new 2.x event-mapping case. Interactive desktop behavior remains subject to the earlier WindowServer sandbox limitation.

## Arrange styles

The menu-bar **Arrange pets** item is now a submenu with seven layouts: Grid (the original right-to-left, bottom-up packing), Align left, Align right, Align top, Align bottom, Center, and Random scatter. The layout math lives in `PetCore/Arrangement.swift` so it is testable without AppKit. It uses each pet's current window size, clamps every window to the visible frame, wraps edge stacks into additional columns or rows, centers a compact grid, and places random-scatter pets with rejection sampling so they do not overlap where space allows. Arranging stops active walks and saves the new positions. The target display is the one currently holding most of the group, falling back to the screen under the pointer.

Nine new tests cover exact grid and edge placements (including wrapping into a second row or column), alignment for pets of different sizes, centered-block geometry for equal and mixed sizes, random scatter containment and non-overlap, containment for every style on a screen with negative coordinates, metadata, and degenerate inputs. `swift test` passes all 39 PetCore tests and the debug app target builds. The menu itself and interactive placement still require a graphical desktop; they could not be exercised under the earlier WindowServer restriction.
