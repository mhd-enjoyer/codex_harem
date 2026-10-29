# Codex Harem

Multiple animated pets on your macOS desktop, following your coding-agent harnesses: Codex, Claude Code, and opencode. A small native Swift package with no third-party dependencies or API key requirement.

Each pet has its own transparent, floating window. Add as many instances as you want, including duplicates. Drag to move, click to wave, and right-click to select a thread, resize, or remove. The horned anime menu-bar icon adds pets, arranges them, and hides or shows the group. Layout and thread bindings survive restarts. Pets appear across Spaces and alongside fullscreen apps; they don't take keyboard focus.

Right-click an individual pet and enable **Walk around** to let it take occasional short strolls while idle (or after its completion review finishes). Each pet's toggle is independent, off by default, and saved with its layout. Walks stay within the current screen and pause when you hover, drag, hide the pet, enable Reduce Motion, or a task changes its status. Position is saved at the end of each walk.

Right-click a pet and choose **Animation speed** to select Slow (40%), Relaxed (65%, the new default), Original (100%), or Fast (125%). This preference is saved per instance. The percentages scale the previous frame rates, not a verified built-in Codex timing specification. All frames still play; loops take longer. Walking movement and one-shot gesture durations use the same rate so slower jumps finish and walking stays in step. For example, the six-frame active-work loop now takes about 1.15 seconds at the default, rather than 0.75 seconds.

## Run

Requires macOS 13+, Swift 6+ to build, and an installed Codex CLI. The shared-server integration is tested against the protocol schema from Codex CLI 0.163.0.

```sh
swift run codex-harem
```

Or build a double-clickable app and zip:

```sh
./scripts/package.sh
open 'dist/Codex Harem.app'
```

Copy the app to Applications if desired. The local bundle uses an ad-hoc signature; distribution to other Macs would require Developer ID signing and notarization.

Start with a safe demonstration of every status:

```sh
swift run codex-harem --demo
```

The packaged app initializes its own artwork library from bundled local copies on first launch. Its first layout displays Codex, Dewey, and Fireball when installed. Artwork is loaded exclusively from `~/Library/Application Support/CodexHarem/Pets/*/pet.json`; normal launches never read Codex's artwork cache or custom-pet folder. The initial copy runs once, preserves existing IDs, and does not restore pets you later delete. Layout, walking preferences, and playback speeds remain in the separate `pets.json` file.

Use **Open pet folder** in the menu-bar icon to edit this library, and **Reload pets** after adding or editing artwork. `--pets PATH` replaces the library location entirely; it does not add Codex artwork or bundled seeds to that directory.

For a source build without bundled artwork, import your existing cached Codex pets once:

```sh
swift run codex-harem --import-codex
# Or import a standalone pet folder:
swift run codex-harem --import-pet /path/to/my-pet
```

Imports validate and copy only the manifest and spritesheet into the independent library. Existing IDs are kept, and Codex's original files are never modified. Once copied, the pets continue to load even if the original source is unavailable. Importing from Codex is explicit; it is not part of ordinary loading.

The local packaging script optionally bundles the standalone `pets/` directory as first-launch seeds. To populate that directory before building:

```sh
swift run codex-harem --pets ./pets --import-codex
./scripts/package.sh
```

Local artwork is excluded from source control. The app zip built in this workspace includes the nine local copies imported for this user; distributing that zip also distributes those images.

## Status syncing

Each pet picks which harness it listens to: all harnesses, Codex, Claude Code, or opencode (right-click → **Listen to**). The "Follow thread" list only offers threads from the chosen harness, and switching harnesses drops a binding that belongs to another one. Thread IDs are namespaced per provider, so bindings never collide and saved layouts keep working across updates.

The Codex companion connects with `codex app-server proxy` to the existing shared app-server socket. It initializes its own client, polls `thread/list`, and separately reads **all loaded threads**, including active threads older than the recent-history page. Reads use `includeTurns: false`; it never starts/resumes a conversation, changes Codex settings, sends a prompt, approves a tool, or requires a separate sign-in. Runtime status polling is once per second. Server-reported unloaded/idle states cannot be revived by stale active log records; only current log events enrich active work or preserve a recent terminal outcome. It also reduces lifecycle notifications when received. This protocol is documented in [Codex App Server](https://learn.chatgpt.com/docs/app-server).

| Codex state | Pet behavior |
| --- | --- |
| Idle | Calm idle loop, occasional wave or hop |
| Active/thinking | Active-work animation |
| Executing tools | Active-work animation |
| Waiting for approval/input | Expectant animation and “Waiting” badge |
| Failed / system error | Failure animation and “Failed” badge |
| Interrupted | Failure reaction with interrupted status |
| Completed | Review animation, then resting pose |
| Not loaded/unavailable | Dimmed resting pose if no rollout evidence is available |

A pet can follow a particular thread, the latest updated thread, or all threads. For “all,” waiting takes priority over working/thinking; when nothing is active, the most recently updated thread supplies the result. Old failures do not override current work. Individual bindings keep parallel conversations independent.

If the shared daemon is unavailable (including older Codex versions), the companion automatically reads recent session JSONL files under `$CODEX_HOME/sessions` and retries the proxy every ten seconds. It reads the latest 64 session files incrementally, retains partial writes, and handles truncation and atomic file replacement. The horned anime menu-bar icon identifies this degraded mode. **Session logs cannot reliably expose pending approvals or an abruptly killed Codex process**, and a final logged active state can remain active until another event arrives. Exact waiting/idle runtime status requires the shared-server connection. No inference requests are made by the companion.

### Claude Code

Claude Code needs no setup and no hooks: the companion tails session transcripts under `~/.claude/projects` (latest 64, incremental, partial-write safe) once per second, exactly like the Codex log fallback. Tool calls map to working, model text and reasoning to thinking, a finished turn marker to completed, and thread names come from generated session titles or the project folder. **Transcripts cannot expose permission prompts, so the waiting animation never appears for Claude Code**, and a session interrupted without further writes may keep its last status. Use `--claude-home` to point at a different Claude data directory.

### opencode

If an `opencode` CLI is found on `PATH` (or passed with `--opencode`), the companion spawns `opencode serve` on a free localhost port and observes it like the Codex shared server: one poll per second of `/session` (titles, timestamps) and `/session/status` (busy/retry/idle), plus the `/event` SSE stream for permission requests (waiting), permission replies, turn completion, and errors (aborted turns show interrupted, other errors failed). Sessions you run in the opencode TUI appear in the list because the server reads the same shared storage. Set `OPENCODE_SERVER_PASSWORD` if you want the spawned server protected with basic auth; the companion sends the credentials automatically.

The default Codex home is `$CODEX_HOME`, falling back to `~/.codex`. Layout is stored separately at `~/Library/Application Support/CodexHarem/pets.json`.

```sh
codex-harem --home /path/to/codex-home --codex /absolute/path/to/codex
codex-harem --claude-home /path/to/claude-home --opencode /absolute/path/to/opencode
codex-harem --pets /path/to/independent-pets --config /path/to/layout.json
codex-harem --diagnose
codex-harem --probe 10
```

## Sprite compatibility

Loads installed built-in and custom `pet.json` manifests from the independent library with `id`, `displayName`, `spritesheetPath`, and `spriteVersionNumber`. Standard v1 sheets have eight columns and nine rows; v2 adds two rows for sixteen clockwise look directions starting at up. v2 pets look toward the nearby cursor while resting. Directional walking plays during dragging and optional idle strolls. System Reduce Motion preferences suppress motion.

Optional `frame: {width,height,columns,rows}` and `animations` overrides support custom sheets. Each animation is `{ "frames": [0, 1, 2], "fps": 8 }`, using zero-based row-major indices. Override names: `idle`, `walkRight`, `walkLeft`, `wave`, `hop`, `failed`, `thinking` (expectant pose), `working` (active work), `completed` (review). Per-pet playback speed scales these authored frame rates. Grid coverage, frame bounds, frame rates, versions, and sprite path containment are checked before use. This validates renderer compatibility, not artwork quality.

## Verification

```sh
swift test
python3 scripts/test-proxy.py  # after swift build
.build/debug/codex-harem --diagnose
.build/debug/codex-harem --render-contact /tmp/pets.png
.build/debug/codex-harem --demo --config /tmp/pet-layout.json --smoke /tmp/pet-windows
```

`--smoke` runs the desktop app, renders its visible pet windows to PNG, and exits. It requires a normal macOS graphical login with WindowServer access. `--render-contact` renders installed sprite frames without launching the desktop UI. The proxy fixture validates the real transport's handshake, status transitions, and loaded-thread reads without issuing Codex model requests. `--probe N` prints one merged snapshot per second from all three harnesses, including the spawned opencode server.

In a restricted build sandbox, point Swift's caches at a writable temporary directory:

```sh
CLANG_MODULE_CACHE_PATH=/tmp/harem-clang-cache \
SWIFTPM_MODULECACHE_OVERRIDE=/tmp/harem-swift-cache \
swift test --disable-sandbox
```

The package script uses temporary caches and disables release debug-info generation, which avoids a sandbox-restricted dSYM step. AppKit/WindowServer and the user's live Codex socket may still be inaccessible from such a sandbox. Run the packaged app from Finder to verify desktop interaction and the live shared-server connection.
