// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "SheafnoteCore",
    platforms: [.iOS("26.0"), .macOS("26.0")],
    products: [
        .library(name: "SheafnoteCore", targets: ["SheafnoteCore"]),
    ],
    targets: [
        .target(name: "SheafnoteCore"),
        .testTarget(name: "SheafnoteCoreTests", dependencies: ["SheafnoteCore"]),
    ]
)
