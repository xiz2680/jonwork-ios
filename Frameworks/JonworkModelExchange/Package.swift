// swift-tools-version: 6.2
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription

let package = Package(
    name: "JonworkModelExchange",
    platforms: [
        .iOS(.v13),
        .macOS(.v11),
        .macCatalyst(.v13),
        .tvOS(.v13),
        .visionOS(.v1),
    ],
    products: [
        .library(
            name: "JonworkModelExchange",
            targets: ["JonworkModelExchange"],
        ),
    ],
    targets: [
        .target(
            name: "JonworkModelExchange",
        ),
        .testTarget(
            name: "JonworkModelExchangeTests",
            dependencies: ["JonworkModelExchange"],
        ),
    ],
)
