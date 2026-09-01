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
        // Named by version, not by commit: `wisent-components` 0.7.1 is a
        // tagged release that declares no dependencies of its own, so an exact
        // version requirement is legal here and every consumer in the fleet
        // names the same one. Spis takes no screens from this package — only
        // `wisentEnsureWindow`, the fleet's launch-window guarantee, and the
        // shared skeleton views (`WisentSkeleton`, `WisentSkeletonText`,
        // `WisentSkeletonGroup`, `WisentSkeletonList`) that stand in for a
        // panel while it loads.
        .package(url: "https://github.com/wisent-ai/wisent-components.git", exact: "0.7.1"),
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
