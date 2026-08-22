// swift-tools-version: 5.10

import PackageDescription

let package = Package(
    name: "SpisDesktop",
    platforms: [
        .macOS(.v14)
    ],
    products: [
        .executable(name: "Spis", targets: ["SpisDesktop"])
    ],
    targets: [
        .executableTarget(
            name: "SpisDesktop",
            path: "Sources/SpisDesktop"
        )
    ]
)
