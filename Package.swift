// swift-tools-version: 6.2
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription

let package = Package(
    name: "SelfAuth",
    defaultLocalization: "en",
    platforms: [
        .macOS(.v10_15),
        .iOS(.v13),
        .tvOS(.v13),
        .watchOS(.v6),
    ],
    dependencies: [
        .package(url: "https://github.com/apple/swift-nio.git", from: "2.0.0")
    ],
    targets: [
        // Targets are the basic building blocks of a package, defining a module or a test suite.
        // Targets can depend on other targets in this package and products from dependencies.
        .target(
            name: "Libmailer",
            path: "Sources/Libmailer",
            publicHeadersPath: ".",
            linkerSettings: [
                .unsafeFlags(["-L", "Sources/Libmailer"]),
                .linkedLibrary("mailer"),
            ]
        ),
        .executableTarget(
            name: "SelfAuth",
            dependencies: [
                "Libmailer",
                .product(name: "NIO", package: "swift-nio"),
                .product(name: "NIOHTTP1", package: "swift-nio"),
            ],
            path: "Sources",
            resources: [
                .copy("Resources")
            ],
            swiftSettings: [
                .unsafeFlags(["-parse-as-library"])
            ],
        ),
    ]
)
