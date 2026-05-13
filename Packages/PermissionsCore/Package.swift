// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "PermissionsCore",
    platforms: [.macOS(.v14)],
    products: [
        .library(name: "PermissionsCore", targets: ["PermissionsCore"]),
    ],
    targets: [
        .target(name: "PermissionsCore"),
        .testTarget(
            name: "PermissionsCoreTests",
            dependencies: ["PermissionsCore"]
        ),
    ]
)
