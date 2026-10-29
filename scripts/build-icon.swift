import Foundation
import CoreGraphics
import ImageIO

// Build native 1x/2x representations from the generated artwork. The delivery
// mask gives every size a consistent rounded tile and clean transparent margin.
guard CommandLine.arguments.count == 3 else {
    fputs("Usage: swift build-icon.swift SOURCE.png OUTPUT.iconset\n", stderr)
    exit(1)
}
let sourceURL = URL(fileURLWithPath: CommandLine.arguments[1])
let output = URL(fileURLWithPath: CommandLine.arguments[2])
guard let source = CGImageSourceCreateWithURL(sourceURL as CFURL, nil),
      let image = CGImageSourceCreateImageAtIndex(source, 0, nil), image.width == image.height else {
    fputs("App icon source must be a readable square image\n", stderr)
    exit(1)
}
try FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)
for points in [16, 32, 128, 256, 512] {
    for scale in [1, 2] {
        let pixels = points * scale
        let side = CGFloat(pixels)
        guard let context = CGContext(data: nil, width: pixels, height: pixels, bitsPerComponent: 8,
                                      bytesPerRow: 0, space: CGColorSpaceCreateDeviceRGB(),
                                      bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { exit(1) }
        let rect = CGRect(x: 0, y: 0, width: side, height: side)
        let tile = rect.insetBy(dx: side * 0.05, dy: side * 0.05)
        context.addPath(CGPath(roundedRect: tile, cornerWidth: side * 0.18, cornerHeight: side * 0.18, transform: nil))
        context.clip()
        context.interpolationQuality = .high
        context.draw(image, in: rect)
        let suffix = scale == 2 ? "@2x" : ""
        let file = output.appendingPathComponent("icon_\(points)x\(points)\(suffix).png")
        guard let rendered = context.makeImage(),
              let destination = CGImageDestinationCreateWithURL(file as CFURL, "public.png" as CFString, 1, nil) else { exit(1) }
        CGImageDestinationAddImage(destination, rendered, nil)
        guard CGImageDestinationFinalize(destination) else { exit(1) }
    }
}

// ICNS supports PNG-backed chunks directly. Writing the container avoids an
// iconutil dependency on system services that may be denied in build sandboxes.
func bigEndianWord(_ number: Int) -> Data {
    var word = UInt32(number).bigEndian
    return withUnsafeBytes(of: &word) { Data($0) }
}
let representations = [
    ("icp4", "icon_16x16.png"), ("ic11", "icon_16x16@2x.png"),
    ("icp5", "icon_32x32.png"), ("ic12", "icon_32x32@2x.png"),
    ("ic07", "icon_128x128.png"), ("ic13", "icon_128x128@2x.png"),
    ("ic08", "icon_256x256.png"), ("ic14", "icon_256x256@2x.png"),
    ("ic09", "icon_512x512.png"), ("ic10", "icon_512x512@2x.png")
]
var chunks = Data()
for (type, filename) in representations {
    let png = try Data(contentsOf: output.appendingPathComponent(filename))
    chunks.append(Data(type.utf8)); chunks.append(bigEndianWord(png.count + 8)); chunks.append(png)
}
var icns = Data("icns".utf8)
icns.append(bigEndianWord(chunks.count + 8)); icns.append(chunks)
try icns.write(to: output.deletingPathExtension().appendingPathExtension("icns"), options: .atomic)
