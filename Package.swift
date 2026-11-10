// swift-tools-version: 5.9
import PackageDescription
let package = Package(
    name: "WazKit",
    platforms: [.macOS(.v14), .iOS(.v17)],
    products: [
        .library(name: "WazKit", targets: ["WazKit"]),
    ],
    targets: [
        .target(name: "WazKit"),
    ]
)
