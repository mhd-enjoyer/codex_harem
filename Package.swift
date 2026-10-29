// swift-tools-version: 6.0
import PackageDescription
let package = Package(
    name: "CodexHarem", platforms: [.macOS(.v13)],
    products: [.executable(name: "codex-harem", targets: ["CodexHarem"]), .library(name: "PetCore", targets: ["PetCore"])],
    targets: [.target(name: "PetCore"), .executableTarget(name: "CodexHarem", dependencies: ["PetCore"]), .testTarget(name: "PetCoreTests", dependencies: ["PetCore"])],
    swiftLanguageModes: [.v5]
)
