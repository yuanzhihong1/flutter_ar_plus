// swift-tools-version: 5.9
// swift-tools-version 声明构建此包所需的最低 Swift 版本。

import PackageDescription

let package = Package(
    name: "flutter_ar_plus",
    platforms: [
        .macOS("12.0")
    ],
    products: [
        .library(name: "flutter_ar_plus", targets: ["flutter_ar_plus"])
    ],
    dependencies: [
        .package(name: "FlutterFramework", path: "../FlutterFramework")
    ],
    targets: [
        .target(
            name: "flutter_ar_plus",
            dependencies: [
                .product(name: "FlutterFramework", package: "FlutterFramework")
            ],
            resources: [
                // 插件已经包含隐私清单，发布时会随资源包一起处理。
                .process("PrivacyInfo.xcprivacy"),

                // 如需将其他资源打包进插件，请参阅以下文档：
                // https://developer.apple.com/documentation/xcode/bundling-resources-with-a-swift-package
            ]
        )
    ]
)
