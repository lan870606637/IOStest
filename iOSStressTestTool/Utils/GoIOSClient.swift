import Foundation

// MARK: - go-ios 客户端
/// 封装 go-ios (ios) 命令行工具，用于真机操作。
///
/// 为什么需要这个：原实现用 Facebook 的 idb 做真机 UI 控制，但
/// `brew install idb-companion` 的 formula 已从 Homebrew 下架，新机器装不上；
/// 而 go-ios 是单体静态二进制，本项目已内置一份 (.tools/go-ios/ios)，
/// 且自带隧道、截图、App 生命周期与 UI 控制能力，因此作为首选实现。
///
/// 能力分三档，务必区分，避免误判"真机可用了"：
///  1. 免签名：设备列表、tunnel、screenshot、launch、kill、install、uninstall
///  2. 需签名：ui tap/swipe/longpress/type/button
///     （需要先在设备上装好 WDA 或 DeviceKit，二者都要 p12 + mobileprovision）
///  3. 不支持：shake（无对应命令）
@MainActor
final class GoIOSClient {
    static let shared = GoIOSClient()

    private let runner = ProcessRunner.shared
    private let logger = Logger.shared

    private init() {}

    // MARK: - 工具发现

    /// 候选路径：App 运行时目录优先，其次是 Homebrew 安装的副本
    private nonisolated static var candidatePaths: [String] {
        var paths: [String] = []
        paths.append(HostEnvironment.runtimeDirectory + "/go-ios/ios")
        paths.append("/opt/homebrew/bin/ios")
        paths.append("/usr/local/bin/ios")
        return paths
    }

    private lazy var toolPath: String? = {
        for path in Self.candidatePaths where FileManager.default.isExecutableFile(atPath: path) {
            return path
        }
        return nil
    }()

    /// go-ios 是否可用（免签名能力）
    var isAvailable: Bool { toolPath != nil }

    /// 静态探测：供设置页/启动自检在不创建实例的情况下判断工具是否存在。
    /// 标记 nonisolated，便于从非 MainActor 上下文（如 AppDelegate 自检）调用。
    nonisolated static var isToolAvailable: Bool {
        for path in Self.candidatePaths where FileManager.default.isExecutableFile(atPath: path) {
            return true
        }
        return false
    }

    /// 展示用的工具路径，用于设置页显示
    nonisolated static var displayPath: String {
        for path in Self.candidatePaths where FileManager.default.isExecutableFile(atPath: path) {
            return path
        }
        return "未安装"
    }

    /// UI 自动化驱动模式。真机上 UI 控制需要 WDA 或 DeviceKit，
    /// 可通过环境变量 GO_IOS_UI_DRIVER 覆盖（go-ios 自身也读这个变量）。
    private var driverArguments: [String] {
        if let driver = ProcessInfo.processInfo.environment["GO_IOS_UI_DRIVER"], !driver.isEmpty {
            return ["--driver=\(driver)"]
        }
        return []
    }

    /// go-ios agent 环境变量，与 ScreenshotService 保持一致
    private var agentEnvironment: [String: String] {
        ["ENABLE_GO_IOS_AGENT": "user"]
    }

    // MARK: - 底层执行

    @discardableResult
    private func run(_ arguments: [String],
                     timeout: TimeInterval = 60,
                     environment: [String: String]? = nil) async -> ProcessResult {
        guard let toolPath else {
            return ProcessResult(
                exitCode: -1,
                stdout: "",
                stderr: "go-ios 未找到。请确认 .tools/go-ios/ios 存在，或执行 brew install go-ios"
            )
        }
        return await runner.runAsync(
            toolPath,
            arguments: arguments,
            timeout: timeout,
            environment: environment ?? agentEnvironment
        )
    }

    // MARK: - 隧道 (iOS 17+ 必需)

    /// 确保设备隧道已建立。iOS 17+ 的截图/UI 操作都走 CoreDevice 隧道。
    func ensureTunnel(udid: String) async -> Bool {
        let listResult = await run(["tunnel", "ls"], timeout: 20)
        if listResult.stdout.contains(udid) {
            return true
        }

        logger.info("go-ios: 为设备 \(udid) 建立 userspace 隧道")
        let startResult = await run(
            ["tunnel", "start", "--udid=\(udid)", "--userspace"],
            timeout: 90
        )
        guard startResult.isSuccess else {
            logger.warning("go-ios 隧道建立失败: \(startResult.stderr.prefix(200))")
            return false
        }

        // 等隧道在 RSD 上注册完成
        try? await Task.sleep(nanoseconds: 3_000_000_000)
        return true
    }

    // MARK: - 截图

    /// 真机截图（免签名，走 DVT 通道）
    ///
    /// iOS 17+ 必须先把 CoreDevice 隧道建起来才能截图；老系统直接走 usbmuxd 即可。
    /// 因此先直接截一次，失败再建隧道重试，避免给老设备白等隧道超时。
    func screenshot(udid: String, outputPath: String) async -> Bool {
        if await runScreenshot(udid: udid, outputPath: outputPath) {
            return true
        }

        logger.info("go-ios 直连截图失败，尝试建立隧道后重试 (iOS 17+ 需要)")
        guard await ensureTunnel(udid: udid) else { return false }
        return await runScreenshot(udid: udid, outputPath: outputPath)
    }

    private func runScreenshot(udid: String, outputPath: String) async -> Bool {
        let result = await run(
            ["screenshot", "--udid=\(udid)", "--output=\(outputPath)"],
            timeout: 90
        )
        guard result.isSuccess else {
            logger.warning("go-ios 截图失败: \(result.stderr.prefix(200))")
            return false
        }
        return true
    }

    // MARK: - App 生命周期（免签名）

    /// 启动 App。--wait 让命令阻塞到 App 退出，压测场景下不能用，
    /// 因此这里只发启动请求就返回。
    func launchApp(udid: String, bundleID: String) async -> Bool {
        let result = await run(["launch", bundleID, "--udid=\(udid)"], timeout: 60)
        if !result.isSuccess {
            logger.warning("go-ios 启动 App 失败 (\(bundleID)): \(result.stderr.prefix(200))")
        }
        return result.isSuccess
    }

    /// 终止 App
    func terminateApp(udid: String, bundleID: String) async -> Bool {
        let result = await run(["kill", bundleID, "--udid=\(udid)"], timeout: 60)
        if !result.isSuccess {
            logger.warning("go-ios 终止 App 失败 (\(bundleID)): \(result.stderr.prefix(200))")
        }
        return result.isSuccess
    }

    /// 安装 App（.app 目录或 .ipa）
    func installApp(udid: String, path: String) async -> Bool {
        let result = await run(["install", path, "--udid=\(udid)"], timeout: 300)
        if !result.isSuccess {
            logger.warning("go-ios 安装 App 失败: \(result.stderr.prefix(200))")
        }
        return result.isSuccess
    }

    /// 卸载 App
    func uninstallApp(udid: String, bundleID: String) async -> Bool {
        let result = await run(["uninstall", bundleID, "--udid=\(udid)"], timeout: 120)
        return result.isSuccess
    }

    // MARK: - UI 控制（需要 WDA / DeviceKit 已安装并签名）

    /// UI 自动化后端是否就绪。用于在失败时给出准确提示，
    /// 而不是让用户以为是坐标或代码问题。
    func isUIBackendReady() async -> Bool {
        guard isAvailable else { return false }
        let result = await run(["ui", "status"] + driverArguments, timeout: 30)
        return result.isSuccess
    }

    func tap(udid: String, x: Int, y: Int) async -> Bool {
        await uiCommand(["ui", "tap", "--x=\(x)", "--y=\(y)"], udid: udid,
                    action: "点击 (\(x),\(y))")
    }

    func swipe(udid: String, startX: Int, startY: Int, endX: Int, endY: Int, duration: Double) async -> Bool {
        await uiCommand([
            "ui", "swipe",
            "--from-x=\(startX)", "--from-y=\(startY)",
            "--to-x=\(endX)", "--to-y=\(endY)",
            "--duration=\(String(format: "%.1f", duration))",
        ], udid: udid, action: "滑动 (\(startX),\(startY))→(\(endX),\(endY))")
    }

    func longPress(udid: String, x: Int, y: Int, duration: Double) async -> Bool {
        await uiCommand([
            "ui", "longpress", "--x=\(x)", "--y=\(y)",
            "--duration=\(String(format: "%.1f", duration))",
        ], udid: udid, action: "长按 (\(x),\(y))")
    }

    func typeText(udid: String, text: String) async -> Bool {
        await uiCommand(["ui", "type", "--text=\(text)"], udid: udid, action: "输入文字")
    }

    /// 硬件按钮。WDA 只支持 home，锁屏/音量需要 --driver=devicekit
    func pressButton(udid: String, button: String) async -> Bool {
        await uiCommand(["ui", "button", button], udid: udid, action: "按下按钮 \(button)")
    }

    /// 统一的 UI 命令执行 + 错误归类
    private func uiCommand(_ arguments: [String], udid: String, action: String) async -> Bool {
        guard isAvailable else {
            logger.error("真机操作需要 go-ios，尚未安装。可执行 brew install go-ios")
            return false
        }

        let result = await run(arguments + ["--udid=\(udid)"] + driverArguments, timeout: 90)
        guard result.isSuccess else {
            let stderr = result.stderr
            // 后端缺失是最常见的失败原因，单独给出可操作的提示
            if stderr.contains("no UI automation backend reachable") {
                logger.error("""
                    真机 UI 控制不可用：未检测到 WDA 或 DeviceKit 后端。
                    请先安装并签名（需要 p12 + mobileprovision）：
                      ios ui install wda --p12file=<证书> --profile=<描述文件>
                    或构建 DeviceKit：ios ui install devicekit --p12file=<证书> --profile=<描述文件>
                """)
            } else {
                logger.warning("go-ios \(action) 失败: \(stderr.prefix(300))")
            }
            return false
        }
        return true
    }
}
