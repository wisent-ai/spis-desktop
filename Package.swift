// swift-tools-version: 5.10

import PackageDescription

let package = Package(
    name: "ReferenceEngineDesktop",
    platforms: [
        .macOS(.v14)
    ],
    products: [
        .executable(name: "ReferenceEngine", targets: ["ReferenceEngineDesktop"])
    ],
    targets: [
        .executableTarget(
            name: "ReferenceEngineDesktop",
            path: "Sources/ReferenceEngineDesktop"
        )
    ]
)
