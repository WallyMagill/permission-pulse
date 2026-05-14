// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "PermissionsScanners",
    platforms: [.macOS(.v14)],
    products: [
        .library(name: "PermissionsScanners", targets: ["PermissionsScanners"]),
    ],
    dependencies: [
        .package(path: "../PermissionsCore"),
        .package(url: "https://github.com/groue/GRDB.swift", from: "7.10.0"),
    ],
    targets: [
        .target(
            name: "PermissionsScanners",
            dependencies: [
                "PermissionsCore",
                .product(name: "GRDB", package: "GRDB.swift"),
            ]
        ),
        .testTarget(
            name: "PermissionsScannersTests",
            dependencies: [
                "PermissionsScanners",
                "PermissionsCore",
                .product(name: "GRDB", package: "GRDB.swift"),
            ]
        ),
    ]
)
