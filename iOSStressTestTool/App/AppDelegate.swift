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

        if runner.isToolAvailable("/usr/local/bin/idb") {
            logger.info("idb (Facebook iOS Development Bridge) 可用")
        } else {
            logger.info("idb 未安装 (真机操作可能受限)，可通过 brew install idb-companion 安装")
        }
    }
}
