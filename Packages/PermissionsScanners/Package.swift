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
    ],
    targets: [
        .target(
            name: "PermissionsScanners",
            dependencies: ["PermissionsCore"]
        ),
        .testTarget(
            name: "PermissionsScannersTests",
            dependencies: ["PermissionsScanners", "PermissionsCore"]
        ),
    ]
)
