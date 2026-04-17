// swift-tools-version: 5.9
// 备用构建方式: 使用 Swift Package Manager 在命令行编译 macOS 控制端
// 推荐使用 Xcode 打开 .xcodeproj 进行完整构建（包含 XCUITest target）

import PackageDescription

let package = Package(
    name: "iOSStressTestTool",
    platforms: [
        .macOS(.v14)
    ],
    targets: [
        .executableTarget(
            name: "iOSStressTestTool",
            path: "iOSStressTestTool",
            exclude: [
                "Resources/Assets.xcassets/AppIcon.appiconset",
                "Resources/templates",
                "Info.plist",
                "iOSStressTestTool.entitlements",
            ],
            resources: [
                .process("Resources/Assets.xcassets/Contents.json"),
            ],
            swiftSettings: [
                .define("SPM_BUILD"),
            ]
        ),
    ]
)
