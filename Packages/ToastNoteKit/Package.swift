// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "ToastNoteKit",
    platforms: [.macOS(.v14)],
    products: [
        .library(name: "VaultKit", targets: ["VaultKit"]),
        .library(name: "EditorKit", targets: ["EditorKit"]),
        .library(name: "AIFormatKit", targets: ["AIFormatKit"]),
        .library(name: "IndexKit", targets: ["IndexKit"]),
        .library(name: "ExportKit", targets: ["ExportKit"]),
    ],
    dependencies: [
        .package(url: "https://github.com/swiftlang/swift-markdown", from: "0.9.0"),
    ],
    targets: [
        .target(name: "VaultKit"),
        .target(name: "EditorKit", dependencies: [.product(name: "Markdown", package: "swift-markdown")]),
        .target(name: "AIFormatKit", dependencies: ["EditorKit"]),
        .target(name: "IndexKit", dependencies: ["VaultKit", "EditorKit"]),
        .target(
            name: "ExportKit", dependencies: ["EditorKit", .product(name: "Markdown", package: "swift-markdown")],
            resources: [.process("Resources")]
        ),
        .testTarget(name: "VaultKitTests", dependencies: ["VaultKit"]),
        .testTarget(name: "EditorKitTests", dependencies: ["EditorKit"]),
        .testTarget(name: "AIFormatKitTests", dependencies: ["AIFormatKit"]),
        .testTarget(name: "IndexKitTests", dependencies: ["IndexKit"]),
        .testTarget(name: "ExportKitTests", dependencies: ["ExportKit"]),
    ],
    swiftLanguageModes: [.v6]
)
