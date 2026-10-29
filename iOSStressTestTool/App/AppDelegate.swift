import AppKit

class AppDelegate: NSObject, NSApplicationDelegate {
    private let logger = Logger.shared

    func applicationDidFinishLaunching(_ notification: Notification) {
        logger.info("应用启动完成")

        // 检查 Xcode 命令行工具
        checkXcodeTools()

        // 初始化设备轮询
        Task {
            await DeviceService.shared.refreshDevices()
        }

        // 清理旧临时截图
        ScreenshotService.shared.cleanTempScreenshots()
    }

    func applicationWillTerminate(_ notification: Notification) {
        // 保存配置
        AppConfig.shared.save()

        // 停止执行
        EventExecutor.shared.stop()

        // 停止设备轮询
        DeviceService.shared.stopPolling()

        logger.info("应用退出")
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        true
    }

    // MARK: - 环境检查

    private func checkXcodeTools() {
        let runner = ProcessRunner.shared

        if !runner.isToolAvailable("/usr/bin/xcrun") {
            logger.warning("未检测到 Xcode Command Line Tools，请运行: xcode-select --install")
        }

        let simctlResult = runner.xcrun(["simctl", "list", "devices", "--json"])
        if simctlResult.isSuccess {
            logger.info("simctl 可用")
        } else {
            logger.warning("simctl 不可用: \(simctlResult.stderr)")
        }

        if GoIOSClient.isToolAvailable {
            logger.info("go-ios 可用 (\(GoIOSClient.displayPath))，支持真机隧道/截图/App 生命周期")
        } else {
            logger.warning("go-ios 未检测到，真机功能将不可用。请确认 .tools/go-ios/ios 存在")
        }

        if ProcessRunner.shared.isToolAvailable("/usr/local/bin/idb")
            || ProcessRunner.shared.isToolAvailable("/opt/homebrew/bin/idb") {
            logger.info("idb 可用（作为真机 UI 控制的兜底后端）")
        } else {
            logger.info("idb 未安装（该 formula 已从 Homebrew 下架，属正常情况）")
        }
    }
}
