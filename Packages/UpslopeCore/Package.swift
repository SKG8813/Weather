// swift-tools-version:5.10
import PackageDescription

let package = Package(
    name: "UpslopeCore",
    platforms: [.iOS(.v17), .macOS(.v14)],
    products: [
        .library(name: "UpslopeCore", targets: ["UpslopeCore"])
    ],
    targets: [
        .target(name: "UpslopeCore"),
        .testTarget(
            name: "UpslopeCoreTests",
            dependencies: ["UpslopeCore"],
            resources: [.copy("Fixtures")]
        )
    ],
    swiftLanguageVersions: [.v5]
)
