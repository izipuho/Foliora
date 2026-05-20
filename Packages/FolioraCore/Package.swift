// swift-tools-version: 6.3

import PackageDescription

let package = Package(
    name: "FolioraCore",
    platforms: [
        .iOS(.v26)
    ],
    products: [
        .library(name: "Core", targets: ["Core"]),
        .library(name: "DesignSystem", targets: ["DesignSystem"]),
        .library(name: "CollectionDomain", targets: ["CollectionDomain"])
    ],
    targets: [
        .target(name: "Core"),
        .target(name: "DesignSystem"),
        .target(name: "CollectionDomain")
    ]
)
