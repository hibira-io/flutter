// swift-tools-version: 5.9

import PackageDescription

let package = Package(
    name: "hibira_push",
    platforms: [
        .iOS("15.0")
    ],
    products: [
        .library(name: "hibira-push", targets: ["hibira_push"])
    ],
    dependencies: [
        .package(name: "FlutterFramework", path: "../FlutterFramework"),
        .package(url: "https://github.com/hibira-io/hibira-push-ios", from: "1.1.0"),
    ],
    targets: [
        .target(
            name: "hibira_push",
            dependencies: [
                .product(name: "FlutterFramework", package: "FlutterFramework"),
                .product(name: "HibiraPush", package: "hibira-push-ios"),
            ],
            resources: [
                .process("PrivacyInfo.xcprivacy"),
            ]
        )
    ]
)
