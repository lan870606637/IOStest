import SwiftUI

/// iOS 宿主 App 占位界面。
///
/// 存在的唯一目的：给 `iOSStressTestUITests` 提供一个 iOS 平台的被测宿主。
///
/// 为什么必须单独做一个 iOS App：XCUITest 包（`com.apple.product-type.bundle.ui-testing`）
/// 必须挂在一个 iOS 应用上才能被 `xcodebuild test -destination 'platform=iOS...'`
/// 安装到 iPhone。原先工程里 UI 测试包的 `TEST_HOST` 指向的是
/// `iOSStressTestTool.app/Contents/MacOS/iOSStressTestTool`——那是 macOS 的
/// 目录结构，导致测试包只能在 Mac 上跑，永远上不了真机。
///
/// 真正的被测 App 由 UITest 通过环境变量 `STRESS_TEST_BUNDLE_ID` 指定，
/// 不依赖这个宿主，所以这里保持最小实现即可。
@main
struct IOSStressTestHostApp: App {
    var body: some Scene {
        WindowGroup {
            VStack(spacing: 16) {
                Image(systemName: "hammer.fill")
                    .font(.system(size: 48))
                    .foregroundStyle(.tint)
                Text("iOS 压测宿主")
                    .font(.title2.weight(.semibold))
                Text("本 App 仅作为 XCUITest 的宿主占位。\n被测目标由 STRESS_TEST_BUNDLE_ID 指定。")
                    .font(.footnote)
                    .multilineTextAlignment(.center)
                    .foregroundStyle(.secondary)
            }
            .padding()
        }
    }
}
