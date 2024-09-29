// swift-tools-version:6.0
import PackageDescription

let package = Package(
    name: "SwiftBible",
    platforms: [
        .iOS(.v15),
        .macOS(.v12)
    ],
    products: [
        .library(
            name: "SwiftBible",
            targets: ["SwiftBible"]),
    ],
    dependencies: [],
    targets: [
        .target(
            name: "SwiftBible",
            dependencies: []),
    ]
)
