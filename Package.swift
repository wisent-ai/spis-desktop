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
        .package(url: "https://github.com/wisent-ai/wisent-desktop-update.git", exact: "0.1.0"),
        // Pinned to the revision the rest of the fleet consumes (the commit tag
        // 0.2.2 points at); `wisent-components` names `wisent-errors` by commit,
        // and SwiftPM refuses a version requirement on a package that itself
        // requires one by revision. Spis uses exactly one symbol from this
        // package — `wisentEnsureWindow`, the fleet's launch-window guarantee —
        // and none of its views: this app stays the one that does not adopt the
        // design system's screens.
        .package(url: "https://github.com/wisent-ai/wisent-components.git", revision: "63aab577abc78c4d1993a711236479dbc2c2571a"),
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
