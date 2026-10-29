import Foundation
import PetCore

struct ImportReport {
    var copied = 0
    var skipped = 0
    var errors: [String] = []
}
func importCodexPets(from home: URL, to directory: URL) -> ImportReport {
    let library = PetLibrary(directory: directory)
    let names = ["codex": "Codex", "dewey": "Dewey", "fireball": "Fireball", "rocky": "Rocky", "seedy": "Seedy", "stacky": "Stacky", "bsod": "BSOD", "null-signal": "Null Signal"]
    var report = ImportReport()
    func install(_ manifest: PetManifest, from source: URL) {
        do {
            if try library.install(manifest, from: source) { report.copied += 1 }
            else { report.skipped += 1 }
        } catch { report.errors.append("\(manifest.id): \(error)") }
    }
    let assets = home.appendingPathComponent("cache/tui-pets/v1/assets")
    for (id, name) in names.sorted(by: { $0.key < $1.key }) {
        let filename = "\(id)-spritesheet-v4.webp"
        if FileManager.default.fileExists(atPath: assets.appendingPathComponent(filename).path) {
            install(PetManifest(id: id, displayName: name, spritesheetPath: filename), from: assets)
        }
    }
    let customs = home.appendingPathComponent("pets")
    for folder in (try? FileManager.default.contentsOfDirectory(at: customs, includingPropertiesForKeys: nil, options: .skipsHiddenFiles)) ?? [] {
        let file = folder.appendingPathComponent("pet.json")
        guard FileManager.default.fileExists(atPath: file.path) else { continue }
        do { install(try JSONDecoder().decode(PetManifest.self, from: Data(contentsOf: file)), from: folder) }
        catch { report.errors.append("\(folder.lastPathComponent): \(error)") }
    }
    return report
}
