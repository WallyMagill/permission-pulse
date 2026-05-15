// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "PermissionsUI",
    platforms: [.macOS(.v14)],
    products: [
        .library(name: "PermissionsUI", targets: ["PermissionsUI"]),
    ],
    dependencies: [
        .package(path: "../PermissionsCore"),
        .package(path: "../PermissionsStore"),
    ],
    targets: [
        .target(
            name: "PermissionsUI",
            dependencies: ["PermissionsCore", "PermissionsStore"]
        ),
        .testTarget(
            name: "PermissionsUITests",
            dependencies: ["PermissionsUI", "PermissionsCore", "PermissionsStore"]
        ),
    ]
)
