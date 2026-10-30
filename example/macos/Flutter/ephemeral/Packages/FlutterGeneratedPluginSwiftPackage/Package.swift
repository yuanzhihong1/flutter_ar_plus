// swift-tools-version: 5.9
// The swift-tools-version declares the minimum version of Swift required to build this package.
//
// Generated file. Do not edit.
//

import PackageDescription

let package = Package(
    name: "FlutterGeneratedPluginSwiftPackage",
    platforms: [
        .macOS("12.0")
    ],
    products: [
        .library(name: "FlutterGeneratedPluginSwiftPackage", type: .static, targets: ["FlutterGeneratedPluginSwiftPackage"])
    ],
    dependencies: [
        .package(name: "flutter_ar", path: "../.packages/flutter_ar"),
        .package(name: "mediapipe_face_mesh", path: "../.packages/mediapipe_face_mesh-3.2.2"),
        .package(name: "FlutterFramework", path: "../.packages/FlutterFramework")
    ],
    targets: [
        .target(
            name: "FlutterGeneratedPluginSwiftPackage",
            dependencies: [
                .product(name: "flutter-ar", package: "flutter_ar"),
                .product(name: "mediapipe-face-mesh", package: "mediapipe_face_mesh"),
                .product(name: "FlutterFramework", package: "FlutterFramework")
            ]
        )
    ]
)
