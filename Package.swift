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
    dependencies: [
        .package(url: "https://github.com/wisent-ai/wisent-errors.git", revision: "b01a0c99766b5c6378ecdbf3921108420ba058f1"),
    ],
    targets: [
        .executableTarget(
            name: "SpisDesktop",
            dependencies: [
                .product(name: "WisentErrors", package: "wisent-errors"),
            ],
            path: "Sources/SpisDesktop"
        )
    ]
)
