import Foundation
import ImageIO

/// An independent on-disk collection. Imports copy only the manifest and its image;
/// after import, no path in the resulting pet points back into Codex's directory.
public struct PetLibrary {
    public let directory: URL
    public init(directory: URL) { self.directory = directory }

    /// Returns false when this ID is already installed. Existing edits are preserved.
    @discardableResult
    public func install(_ manifest: PetManifest, from sourceDirectory: URL) throws -> Bool {
        guard !manifest.id.isEmpty, manifest.id != ".", manifest.id != "..",
              !manifest.id.contains("/"), !manifest.id.contains("\\"),
              !manifest.id.unicodeScalars.contains(where: { CharacterSet.controlCharacters.contains($0) }) else {
            throw PetError.invalid("Pet ID must be a folder name")
        }
        let fm = FileManager.default
        let destination = directory.appendingPathComponent(manifest.id, isDirectory: true)
        if fm.fileExists(atPath: destination.path) { return false }
        let sheet = try manifest.sheetURL(relativeTo: sourceDirectory)
        let data = try Data(contentsOf: sheet)
        guard let source = CGImageSourceCreateWithData(data as CFData, nil),
              let type = CGImageSourceGetType(source) as String?,
              let image = CGImageSourceCreateImageAtIndex(source, 0, nil),
              ["public.png", "org.webmproject.webp"].contains(type) else {
            throw PetError.invalid("Pet spritesheet must be a readable PNG or WebP")
        }
        try manifest.validate(imageWidth: image.width, imageHeight: image.height)
        var installed = manifest
        installed.spritesheetPath = type == "public.png" ? "spritesheet.png" : "spritesheet.webp"
        try fm.createDirectory(at: directory, withIntermediateDirectories: true)
        let staging = directory.appendingPathComponent(".import-\(UUID().uuidString)", isDirectory: true)
        try fm.createDirectory(at: staging, withIntermediateDirectories: false)
        defer { try? fm.removeItem(at: staging) }
        try data.write(to: staging.appendingPathComponent(installed.spritesheetPath), options: .atomic)
        let encoder = JSONEncoder(); encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        try encoder.encode(installed).write(to: staging.appendingPathComponent("pet.json"), options: .atomic)
        try fm.moveItem(at: staging, to: destination)
        return true
    }

    /// Copies missing pets from a standalone library (for example the app's bundled seeds).
    public func seed(from source: URL) -> [String] {
        var errors: [String] = []
        for folder in (try? FileManager.default.contentsOfDirectory(at: source, includingPropertiesForKeys: nil, options: .skipsHiddenFiles)) ?? [] {
            let file = folder.appendingPathComponent("pet.json")
            guard FileManager.default.fileExists(atPath: file.path) else { continue }
            do {
                let manifest = try JSONDecoder().decode(PetManifest.self, from: Data(contentsOf: file))
                try install(manifest, from: folder)
            } catch { errors.append("\(folder.lastPathComponent): \(error)") }
        }
        return errors
    }

    /// First-launch initialization is one-shot, so deleted user pets stay deleted.
    public func initialize(from source: URL) -> [String] {
        let fm = FileManager.default
        let marker = directory.appendingPathComponent(".initialized")
        guard !fm.fileExists(atPath: marker.path), fm.fileExists(atPath: source.path) else { return [] }
        let errors = seed(from: source)
        guard errors.isEmpty else { return errors }
        do {
            try fm.createDirectory(at: directory, withIntermediateDirectories: true)
            try Data("Codex Harem independent library\n".utf8).write(to: marker, options: .atomic)
            return []
        } catch { return ["Cannot initialize pet library: \(error)"] }
    }
}
