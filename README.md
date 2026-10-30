# Codex Harem

Animated pets that live on your macOS desktop and react to your coding agents: Codex, Claude Code, and opencode. Native Swift, no third-party dependencies, no API key, and no model requests — it only reads status.

![Codex Harem](assets/app-icon.png)

## What it does

- **One pet, one window.** Each pet is its own transparent, non-activating floating panel that follows you across Spaces and over fullscreen apps without ever taking keyboard focus. Add as many as you like, including duplicates of the same pet.
- **Status animation.** Each pet picks a harness to listen to (all, Codex, Claude Code, opencode) and optionally a specific thread. Idle pets drift through calm loops; a working agent triggers the active animation; waiting and failed states raise a badge, and hover names the current status. Unavailable threads dim to half opacity instead of disappearing.
- **Direct manipulation.** Drag to move, click to wave, right-click for the per-pet menu: harness, thread binding, size (100–260 pt), animation speed, walk toggle, remove.
- **Menu-bar icon** (the horned anime one) to add pets, open the pet folder, reload artwork, hide or show all pets, and arrange them.
- **Arrangement.** Grid, align left/right/top/bottom, center, or random scatter. Arranging respects each pet's current size, stays inside the visible frame, and wraps into extra rows/columns when space runs out; scatter avoids overlap where it can.
- **Optional idle walking.** Per pet, off by default. Short strolls within the current screen that pause on hover, drag, hide, status change, or Reduce Motion.
- **Persistence.** Positions, sizes, thread bindings, harness choice, walking, and playback speed are saved to `pets.json` and survive restarts.
- **Independent artwork library.** Pets load only from `~/Library/Application Support/CodexHarem/Pets/*/pet.json`; Codex's own artwork cache is touched solely by the explicit one-shot importer.

## What it cannot do

This is a read-only observer. It never sends prompts, approves tools, resumes threads, or changes settings, so it cannot unblock a waiting agent — it just tells you one is waiting.

Per-harness blind spots, in the order they bite:

| Harness | How it reads | Not visible |
| --- | --- | --- |
| **Codex** | Shared app-server socket via `codex app-server proxy`; falls back to tailing `$CODEX_HOME/sessions` JSONL | Fallback mode cannot see pending approvals or a killed CLI process. Only the shared server gives exact waiting/idle states. |
| **Claude Code** | Tails `~/.claude/projects/**/*.jsonl` — no hooks, no setup | Permission prompts are never written to transcripts, so **waiting never appears**. A crashed session keeps its last status for 15 minutes before decaying to idle. |
| **opencode** | Attaches to the registered `opencode serve --service`; otherwise spawns its own server | Attached, TUI sessions are covered. Spawned, only that server's sessions are, and busy state has to be guessed from `opencode.db`, which a 2.x service may hold behind its WAL. Permission requests are never persisted, so waiting depends on the live SSE stream. |

Other honest limits:

- **macOS 13+ only**, and the packaged app is ad-hoc signed. Distributing to other Macs needs Developer ID signing and notarization.
- **Timing is approximate.** Default playback is 65% of the authored frame rate. The 40/65/100/125% menu options are deliberate choices, not verified parity with any original spec.
- **Polling, not push.** Runtime status is re-read once per second. A final logged "active" state can persist until the next event arrives.
- **Bounded history.** The newest 64 session files are read per log-tailed harness, and the *Follow thread* menu lists at most 64 threads.
- **Artwork is yours to audit.** Local `pets/` images are gitignored; a zip built in this workspace embeds copies of whatever they contain, so distributing that zip distributes those images too.
- **Single Mac, no sync.** Nothing leaves the machine, and saved layouts are only as portable as the library paths you point them at.

## Run

Requires macOS 13+ and Swift 6+ to build. Harnesses are optional — install the ones you want watched; a missing one simply never reports.

```sh
swift run codex-harem
```

Build a double-clickable app and zip:

```sh
./scripts/package.sh
open 'dist/Codex Harem.app'
```

Try every status without an agent running:

```sh
swift run codex-harem --demo
```

On first launch the packaged app seeds its own artwork library from bundled copies and shows its first layout. That copy runs once, keeps existing IDs, and never resurrects pets you deleted.

### Flags

| Flag | Meaning |
| --- | --- |
| `--home PATH` | Codex data directory (default `$CODEX_HOME` or `~/.codex`) |
| `--claude-home PATH` | Claude Code data directory (default `~/.claude`) |
| `--pets PATH` | Pet library (default `~/Library/Application Support/CodexHarem/Pets`); replaces the default, does not merge |
| `--config PATH` | Layout file (default `~/Library/Application Support/CodexHarem/pets.json`) |
| `--codex PATH`, `--opencode PATH` | Explicit CLI paths instead of PATH/Homebrew lookup |
| `--import-codex` | Copy cached Codex artwork into the library once, then exit |
| `--import-pet PATH` | Copy one pet folder into the library, then exit (existing IDs kept) |
| `--diagnose` | Validate installed pets and print current session status, then exit |
| `--probe N` | Print one merged snapshot per second for N seconds (1–60) |
| `--render-contact PATH` | Write a PNG of installed pets across animation rows |
| `--demo` | Cycle statuses without connecting to anything |
| `--smoke DIR` | Render visible pet windows to PNG and exit (needs WindowServer) |

Imports validate and copy only the manifest and spritesheet; source files are never modified, and imported pets keep loading after the source disappears.

## Pet artwork

A pet folder needs `pet.json` with `id`, `displayName`, `spritesheetPath`, and `spriteVersionNumber`. Standard v1 sheets are 8 columns × 9 rows; v2 adds two rows of sixteen clockwise look directions starting at up, and v2 pets glance toward the cursor while resting.

Optional `frame: {width,height,columns,rows}` and `animations` overrides support custom sheets. Each animation is `{ "frames": [0, 1, 2], "fps": 8 }` with zero-based row-major indices. Override names: `idle`, `walkRight`, `walkLeft`, `wave`, `hop`, `failed`, `thinking`, `working`, `completed`.

Grid coverage, frame bounds, frame rates, versions, and sprite-path containment are validated before use — that is renderer compatibility, not a judgment on the artwork.

## Verification

```sh
swift test
python3 scripts/test-proxy.py  # after swift build
.build/debug/codex-harem --diagnose
.build/debug/codex-harem --render-contact /tmp/pets.png
```

`scripts/test-proxy.py` drives the real monitor against a fixture executable, covering handshake, transitions, and the dead-proxy fallback without touching your live Codex socket. `VALIDATION.md` records what has actually been verified versus what needs a graphical session.

In a restricted build sandbox:

```sh
CLANG_MODULE_CACHE_PATH=/tmp/harem-clang-cache \
SWIFTPM_MODULECACHE_OVERRIDE=/tmp/harem-swift-cache \
swift test --disable-sandbox
```

`--smoke`, dragging, and live shared-server status all require a normal desktop login; they cannot be validated from a sandbox.

## Credits

- **App icon:** design reference by [zipzippipe](https://github.com/zipzippipe). The full-color master in `assets/app-icon.png` was produced from the maintainer's own character reference; `scripts/build-icon.sh` renders the ICNS set, and the monochrome menu-bar mark is drawn in code (`Sources/CodexHarem/MenuBarIcon.swift`).
- Pet artwork is not included in source control; the sprites shown in local builds come from the user's own library.
