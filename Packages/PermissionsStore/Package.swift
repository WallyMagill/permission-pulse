// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "PermissionsStore",
    platforms: [.macOS(.v14)],
    products: [
        .library(name: "PermissionsStore", targets: ["PermissionsStore"]),
    ],
    dependencies: [
        .package(path: "../PermissionsCore"),
        .package(url: "https://github.com/groue/GRDB.swift", from: "7.10.0"),
    ],
    targets: [
        .target(
            name: "PermissionsStore",
            dependencies: [
                "PermissionsCore",
                .product(name: "GRDB", package: "GRDB.swift"),
            ]
        ),
        .testTarget(
            name: "PermissionsStoreTests",
            dependencies: [
                "PermissionsStore",
                "PermissionsCore",
                .product(name: "GRDB", package: "GRDB.swift"),
            ]
        ),
    ]
)
