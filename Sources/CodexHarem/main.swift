import AppKit
import Darwin
import PetCore

signal(SIGPIPE, SIG_IGN)

let args = Array(CommandLine.arguments.dropFirst())
func option(_ name: String) -> String? {
    guard let index = args.firstIndex(of: name), args.indices.contains(index + 1) else { return nil }
    return args[index + 1]
}
if args.contains("--help") {
    print("""
    codex-harem [--demo] [--home PATH] [--pets PATH] [--config PATH] [--codex PATH]
    codex-harem --diagnose [--home PATH] [--pets PATH]

    Multiple native desktop Codex pets. Drag to move; right-click to bind a thread,
    resize, or remove. Use the horned anime menu-bar icon to add more pets. No API key required.
    --render-contact PATH  Write a PNG of installed pets and animation rows.
    --probe N    Print status snapshots for N seconds (1–60), then exit.
    --smoke DIR  Render each visible pet to DIR and exit after 2 seconds.
    --demo       Cycle through statuses without connecting to Codex.
    --diagnose   Validate installed pets and read current session status, then exit.
    --home       Codex data directory (default: CODEX_HOME or ~/.codex).
    --pets       Independent pet library (default: ~/Library/Application Support/CodexHarem/Pets).
    --import-codex  Copy cached Codex artwork into this library once, then exit.
    --import-pet PATH  Copy a pet folder into this library, then exit (existing IDs are kept).
    --config     Layout file (default: ~/Library/Application Support/CodexHarem/pets.json).
    --codex      Absolute path to Codex CLI (default: search PATH and Homebrew paths).
    """)
    exit(0)
}
let fm = FileManager.default
let home = URL(fileURLWithPath: option("--home") ?? ProcessInfo.processInfo.environment["CODEX_HOME"] ?? fm.homeDirectoryForCurrentUser.appendingPathComponent(".codex").path)
let support = fm.homeDirectoryForCurrentUser.appendingPathComponent("Library/Application Support/CodexHarem")
let petDirectory = URL(fileURLWithPath: option("--pets") ?? support.appendingPathComponent("Pets").path)
if args.contains("--import-codex") {
    let report = importCodexPets(from: home, to: petDirectory)
    print("Copied \(report.copied) pets; kept \(report.skipped) existing pets in \(petDirectory.path)")
    for error in report.errors { fputs("Import error: \(error)\n", stderr) }
    exit(report.errors.isEmpty ? 0 : 1)
}
if let source = option("--import-pet") {
    do {
        let folder = URL(fileURLWithPath: source)
        let manifest = try JSONDecoder().decode(PetManifest.self, from: Data(contentsOf: folder.appendingPathComponent("pet.json")))
        let copied = try PetLibrary(directory: petDirectory).install(manifest, from: folder)
        print("\(copied ? "Imported" : "Kept existing") \(manifest.id) in \(petDirectory.path)")
        exit(0)
    } catch { fputs("Import error: \(error)\n", stderr); exit(1) }
}
// The packaged app ships independent seed copies. Never consult Codex's artwork
// during normal loading, and never seed an explicitly selected library.
var seedErrors: [String] = []
if option("--pets") == nil, !args.contains("--probe"),
   let resources = Bundle.main.resourceURL {
    seedErrors = PetLibrary(directory: petDirectory).initialize(from: resources.appendingPathComponent("Pets"))
}
let catalog = Catalog(directory: petDirectory)
catalog.errors.append(contentsOf: seedErrors)
if let output = option("--render-contact") {
    let pets = catalog.pets.values.sorted { $0.manifest.id < $1.manifest.id }
    let animations = ["idle", "walkRight", "walkLeft", "wave", "hop", "failed", "thinking", "working", "completed"]
    let width = max(1, pets.count) * 96, height = animations.count * 104
    guard let context = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0, space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { exit(1) }
    for (column, pet) in pets.enumerated() {
        for (row, name) in animations.enumerated() {
            if let frame = pet.frame(pet.manifest.animation(name).frames.first ?? 0) {
                context.draw(frame, in: CGRect(x: column * 96, y: height - (row + 1) * 104, width: 96, height: 104))
            }
        }
    }
    guard let image = context.makeImage(), let destination = CGImageDestinationCreateWithURL(URL(fileURLWithPath: output) as CFURL, "public.png" as CFString, 1, nil) else { exit(1) }
    CGImageDestinationAddImage(destination, image, nil)
    guard CGImageDestinationFinalize(destination) else { exit(1) }
    print("Rendered \(pets.count) pets × \(animations.count) animations to \(output)")
    exit(0)
}
if args.contains("--diagnose") {
    print("Pet library: \(petDirectory.path)")
    for pet in catalog.pets.values.sorted(by: { $0.manifest.id < $1.manifest.id }) {
        print("pet \(pet.manifest.id): \(pet.image.width)×\(pet.image.height), \(pet.manifest.columns)×\(pet.manifest.rows) grid")
    }
    for error in catalog.errors { print("warning: \(error)") }
    let monitor = RolloutMonitor(home: home)
    let states = monitor.poll().sorted { $0.updatedAt > $1.updatedAt }
    for state in states.prefix(10) { print("thread \(state.id): \(state.status.rawValue)") }
    print("\(catalog.pets.count) pets, \(states.count) recent threads. Shared-server socket: \(fm.fileExists(atPath: home.appendingPathComponent("app-server-control/app-server-control.sock").path) ? "present" : "absent")")
    exit(catalog.pets.isEmpty || !catalog.errors.isEmpty ? 1 : 0)
}
let paths = (ProcessInfo.processInfo.environment["PATH"] ?? "").split(separator: ":").map(String.init) + ["/opt/homebrew/bin", "/usr/local/bin"]
let executable = option("--codex") ?? paths.map { $0 + "/codex" }.first(where: { fm.isExecutableFile(atPath: $0) }) ?? "/opt/homebrew/bin/codex"
let config = URL(fileURLWithPath: option("--config") ?? support.appendingPathComponent("pets.json").path)
if let seconds = option("--probe").flatMap(Double.init), seconds > 0, seconds <= 60 {
    let probe = Monitor(home: home, executable: executable)
    probe.onUpdate = { states, connection in
        print(connection + " | " + states.prefix(10).map { "\($0.id):\($0.status.rawValue)" }.joined(separator: ", "))
        fflush(stdout)
    }
    probe.start()
    RunLoop.main.run(until: Date().addingTimeInterval(seconds))
    probe.stop()
    exit(0)
}
let app = NSApplication.shared
let delegate = App(catalog: catalog, config: config, monitor: Monitor(home: home, executable: executable), demo: args.contains("--demo"))
app.delegate = delegate
app.run()
