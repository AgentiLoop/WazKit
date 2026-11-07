// swift-tools-version: 5.9
import PackageDescription
let package = Package(
    name: "WazKit",
    platforms: [.macOS(.v14)],
    products: [
        .library(name: "WazKit", targets: ["WazKit"]),
    ],
    targets: [
        .target(name: "WazKit"),
    ]
)
