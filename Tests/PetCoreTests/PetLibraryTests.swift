import XCTest
import CoreGraphics
import ImageIO
@testable import PetCore

final class PetLibraryTests: XCTestCase {
    private func makeSource(in root: URL, id: String = "custom") throws -> URL {
        let folder = root.appendingPathComponent("source")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let manifest = PetManifest(id: id, displayName: "Custom", spritesheetPath: "sheet.png")
        try JSONEncoder().encode(manifest).write(to: folder.appendingPathComponent("pet.json"))
        let context = try XCTUnwrap(CGContext(data: nil, width: 8, height: 9, bitsPerComponent: 8, bytesPerRow: 0,
                                             space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
        let image = try XCTUnwrap(context.makeImage())
        let destination = try XCTUnwrap(CGImageDestinationCreateWithURL(folder.appendingPathComponent("sheet.png") as CFURL, "public.png" as CFString, 1, nil))
        CGImageDestinationAddImage(destination, image, nil)
        XCTAssertTrue(CGImageDestinationFinalize(destination))
        // Unrelated files must never be copied into the artwork library.
        try Data("not artwork".utf8).write(to: folder.appendingPathComponent("unrelated.txt"))
        return folder
    }
    func testImportIsIndependentAndPreservesExistingEdits() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let source = try makeSource(in: root)
        let manifest = try JSONDecoder().decode(PetManifest.self, from: Data(contentsOf: source.appendingPathComponent("pet.json")))
        let library = PetLibrary(directory: root.appendingPathComponent("independent"))
        XCTAssertTrue(try library.install(manifest, from: source))
        let installed = library.directory.appendingPathComponent("custom")
        let files = try FileManager.default.contentsOfDirectory(atPath: installed.path)
        XCTAssertEqual(Set(files), Set(["pet.json", "spritesheet.png"]))
        let manifestURL = installed.appendingPathComponent("pet.json")
        var edited = try JSONDecoder().decode(PetManifest.self, from: Data(contentsOf: manifestURL))
        edited.displayName = "My edit"
        try JSONEncoder().encode(edited).write(to: manifestURL)
        XCTAssertFalse(try library.install(manifest, from: source))
        try FileManager.default.removeItem(at: source)
        let retained = try JSONDecoder().decode(PetManifest.self, from: Data(contentsOf: manifestURL))
        XCTAssertEqual(retained.displayName, "My edit")
        let sheet = try retained.sheetURL(relativeTo: installed)
        XCTAssertNotNil(CGImageSourceCreateWithURL(sheet as CFURL, nil))
    }
    func testInitializeDoesNotRestoreDeletedPetsOnNextLaunch() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let source = try makeSource(in: root)
        let library = PetLibrary(directory: root.appendingPathComponent("independent"))
        XCTAssertTrue(library.initialize(from: root).isEmpty)
        let installed = library.directory.appendingPathComponent("custom")
        XCTAssertTrue(FileManager.default.fileExists(atPath: installed.path))
        try FileManager.default.removeItem(at: installed)
        XCTAssertTrue(library.initialize(from: root).isEmpty)
        XCTAssertFalse(FileManager.default.fileExists(atPath: installed.path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: source.path))
    }
    func testUnsafeImportCannotWriteOutsideLibrary() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let source = try makeSource(in: root)
        let library = PetLibrary(directory: root.appendingPathComponent("independent"))
        let unsafe = PetManifest(id: "../escape", displayName: "Bad", spritesheetPath: "sheet.png")
        XCTAssertThrowsError(try library.install(unsafe, from: source))
        let escapedSheet = PetManifest(id: "safe", displayName: "Bad", spritesheetPath: "../outside.png")
        XCTAssertThrowsError(try library.install(escapedSheet, from: source))
        XCTAssertFalse(FileManager.default.fileExists(atPath: library.directory.path))
    }
}
