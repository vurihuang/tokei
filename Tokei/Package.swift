// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "Tokei",
    platforms: [.macOS(.v13)],
    targets: [
        .executableTarget(
            name: "Tokei",
            path: "Sources/Tokei"
        )
    ]
)
