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
        .package(url: "https://github.com/wisent-ai/wisent-desktop-update.git", exact: "0.2.0"),
        // Pinned to the revision the rest of the fleet consumes;
        // `wisent-components` names `wisent-errors` by commit, and SwiftPM
        // refuses a version requirement on a package that itself requires one
        // by revision. Spis takes two things from this package and no screens:
        // `wisentEnsureWindow`, the fleet's launch-window guarantee, and the
        // shared skeleton views that stand in for a panel while it loads.
        .package(url: "https://github.com/wisent-ai/wisent-components.git", revision: "e52cdda9036b8d44c7ebf51626fcde606e6859b6"),
    ],
    targets: [
        .executableTarget(
            name: "SpisDesktop",
            dependencies: [
                .product(name: "WisentErrors", package: "wisent-errors"),
                .product(name: "WisentDesktopUpdate", package: "wisent-desktop-update"),
                .product(name: "WisentDesignSystem", package: "wisent-components"),
            ],
            path: "Sources/SpisDesktop"
        )
    ]
)
