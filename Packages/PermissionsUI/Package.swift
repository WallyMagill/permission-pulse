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
    ],
    targets: [
        .target(
            name: "PermissionsUI",
            dependencies: ["PermissionsCore"]
        ),
        .testTarget(
            name: "PermissionsUITests",
            dependencies: ["PermissionsUI", "PermissionsCore"]
        ),
    ]
)
