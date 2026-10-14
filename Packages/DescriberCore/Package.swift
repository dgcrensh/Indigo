// swift-tools-version: 5.10

import PackageDescription

let package = Package(
    name: "DescriberCore",
    platforms: [.macOS(.v14)],
    products: [
        .library(name: "DescriberCore", targets: ["DescriberCore"])
    ],
    targets: [
        .target(name: "DescriberCore"),
        .testTarget(name: "DescriberCoreTests", dependencies: ["DescriberCore"]),
    ]
)
