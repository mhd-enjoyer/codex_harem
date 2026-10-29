import AppKit
import PetCore

struct LoadedPet {
    let manifest: PetManifest
    let image: CGImage
    func frame(_ index: Int) -> CGImage? {
        let w = image.width / manifest.columns, h = image.height / manifest.rows
        return image.cropping(to: CGRect(x: index % manifest.columns * w, y: index / manifest.columns * h, width: w, height: h))
    }
}
final class Catalog {
    let directory: URL
    var pets: [String: LoadedPet] = [:]
    var errors: [String] = []
    init(directory: URL) {
        self.directory = directory
        reload()
    }
    func reload() {
        pets.removeAll(); errors.removeAll()
        do {
            let folders = try FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil, options: .skipsHiddenFiles)
            for url in folders.sorted(by: { $0.path < $1.path }) {
                let manifestURL = url.appendingPathComponent("pet.json")
                guard FileManager.default.fileExists(atPath: manifestURL.path) else { continue }
                do {
                    let manifest = try JSONDecoder().decode(PetManifest.self, from: Data(contentsOf: manifestURL))
                    load(manifest, directory: url)
                } catch { errors.append("\(url.lastPathComponent): \(error)") }
            }
        } catch {
            if FileManager.default.fileExists(atPath: directory.path) { errors.append("Cannot read pet library: \(error)") }
        }
    }
    private func load(_ manifest: PetManifest, directory: URL) {
        do {
            let url = try manifest.sheetURL(relativeTo: directory)
            guard FileManager.default.fileExists(atPath: url.path) else { throw PetError.invalid("Missing spritesheet: \(url.lastPathComponent)") }
            guard let source = CGImageSourceCreateWithURL(url as CFURL, nil), let image = CGImageSourceCreateImageAtIndex(source, 0, nil) else {
                throw PetError.invalid("Cannot decode \(url.lastPathComponent)")
            }
            try manifest.validate(imageWidth: image.width, imageHeight: image.height)
            pets[manifest.id] = LoadedPet(manifest: manifest, image: image)
        } catch { errors.append("\(manifest.id): \(error)") }
    }
}
