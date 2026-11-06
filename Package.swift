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
        // The fleet's failure catalogue, named by version rather than by commit:
        // 1.1.0 is the release that declares `refused`, the code a refusal the
        // app reports is filed under. It is taggable because it declares no
        // dependencies of its own.
        .package(url: "https://github.com/wisent-ai/wisent-errors.git", exact: "1.1.0"),
        .package(url: "https://github.com/wisent-ai/wisent-desktop-update.git", exact: "0.2.0"),
        // Named by version, not by commit: `wisent-components` 0.9.1 is a
        // tagged release that declares no dependencies of its own, so an exact
        // version requirement is legal here and every consumer in the fleet
        // names the same one. Spis takes no screens from this package — only
        // `wisentEnsureWindow`, the fleet's launch-window guarantee, the
        // shared skeleton views (`WisentSkeleton`, `WisentSkeletonText`,
        // `WisentSkeletonGroup`, `WisentSkeletonList`) that stand content in
        // place while it is read, and `WisentProgressPanel`, which reports an
        // operation already in flight rather than impersonating content.
        .package(url: "https://github.com/wisent-ai/wisent-components.git", exact: "0.9.1"),
        // Echo 0.1.2 is the fleet's onboarding library, and the only thing
        // Spis takes from it is `WisentOnboarding`: the first-run walkthrough's
        // journey client, its device-scoped storage, and the router that
        // validates the bundled definition. Named by version like every other
        // consumer in the fleet.
        .package(url: "https://github.com/wisent-ai/echo.git", exact: "0.3.0"),
        // The words the walkthrough shows, in every fleet language: the shared
        // wisent-texts catalogue's Swift runtime, reading texts/ of this
        // repository as the bundled Resources/texts.json.
        .package(url: "https://github.com/wisent-ai/wisent-texts.git", exact: "1.0.0"),
    ],
    targets: [
        .executableTarget(
            name: "SpisDesktop",
            dependencies: [
                .product(name: "WisentErrors", package: "wisent-errors"),
                .product(name: "WisentDesktopUpdate", package: "wisent-desktop-update"),
                .product(name: "WisentDesignSystem", package: "wisent-components"),
                .product(name: "WisentOnboarding", package: "echo"),
                .product(name: "WisentTexts", package: "wisent-texts"),
            ],
            path: "Sources/SpisDesktop",
            // Resources/texts/ is the wisent-texts root of this app: the
            // catalogue and translations are its source, bundle.json is what
            // ships (`node ../wisent-texts/bin/texts.mjs --root
            // Sources/SpisDesktop/Resources/texts bundle`).
            exclude: ["Resources/texts/catalogue.json", "Resources/texts/translations"],
            resources: [
                .process("Resources")
            ]
        ),
        // The walkthrough's words in every fleet language, read through the
        // app's own lookup from the bundle it ships (`swift test`).
        .testTarget(
            name: "SpisDesktopTextsTests",
            dependencies: ["SpisDesktop"],
            path: "tests/texts"
        )
    ]
)
