import Foundation
import Combine

// MARK: - 设备服务
/// 管理 iOS 模拟器和真机设备的连接、发现和控制
@MainActor
final class DeviceService: ObservableObject {
    static let shared = DeviceService()

    @Published var devices: [DeviceInfo] = []
    @Published var selectedDevice: DeviceInfo?
    @Published var isPolling = false

    private let runner = ProcessRunner.shared
    private let logger = Logger.shared
    private var pollTimer: Timer?

    private init() {}

    // MARK: - 设备发现

    /// 刷新所有设备列表 (模拟器 + 真机)
    func refreshDevices() async {
        let simulators = await fetchSimulators()
        let physicals = await fetchPhysicalDevices()

        await MainActor.run {
            self.devices = simulators + physicals
            // 如果当前选中设备已断开，清除选中
            if let selected = selectedDevice,
               !devices.contains(where: { $0.udid == selected.udid && $0.status == .connected }) {
                selectedDevice = nil
            }
        }
    }

    /// 获取模拟器列表
    private func fetchSimulators() async -> [DeviceInfo] {
        let result = await runner.simctlAsync(["list", "devices", "--json"])
        guard result.isSuccess, let data = result.stdout.data(using: .utf8) else {
            logger.error("获取模拟器列表失败: \(result.stderr)")
            return []
        }

        do {
            let json = try JSONSerialization.jsonObject(with: data) as? [String: Any]
            let devicesDict = json?["devices"] as? [String: [[String: Any]]] ?? [:]
            var simulators: [DeviceInfo] = []

            for (runtime, deviceList) in devicesDict {
                let osVersion = runtime.components(separatedBy: ".").last?
                    .replacingOccurrences(of: "SimRuntime-iOS-", with: "")
                    .replacingOccurrences(of: "-", with: ".") ?? "Unknown"

                for device in deviceList {
                    guard let udid = device["udid"] as? String,
                          let name = device["name"] as? String,
                          let state = device["state"] as? String,
                          let isAvailable = device["isAvailable"] as? Bool else { continue }

                    let status: DeviceStatus = state == "Booted" ? .connected : .disconnected
                    let screenSize = getSimulatorScreenSize(name: name)

                    simulators.append(DeviceInfo(
                        udid: udid,
                        name: name,
                        deviceType: .simulator,
                        status: status,
                        osVersion: "iOS \(osVersion)",
                        modelName: name,
                        screenWidth: screenSize.width,
                        screenHeight: screenSize.height,
                        isAvailable: isAvailable
                    ))
                }
            }

            return simulators.filter { $0.isAvailable }
        } catch {
            logger.error("解析模拟器JSON失败: \(error)")
            return []
        }
    }

    /// 获取真机设备列表
    private func fetchPhysicalDevices() async -> [DeviceInfo] {
        // 方法1: 使用 xcrun xctrace
        let result = await runner.runAsync("/usr/bin/xcrun", arguments: ["xctrace", "list", "devices"])
        guard result.isSuccess else {
            logger.warning("xcrun xctrace 获取真机列表失败，尝试 idb")
            return await fetchPhysicalDevicesViaIDB()
        }

        var physicals: [DeviceInfo] = []
        let lines = result.stdout.components(separatedBy: "\n")
        var inDevicesSection = false

        for line in lines {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.contains("== Devices ==") {
                inDevicesSection = true
                continue
            }
            if trimmed.contains("== Simulators ==") {
                break
            }
            if inDevicesSection && !trimmed.isEmpty {
                // 格式: DeviceName (OSVersion) (UDID)
                if let parsed = parseXCTraceDeviceLine(trimmed) {
                    physicals.append(parsed)
                }
            }
        }

        return physicals
    }

    /// 通过 idb 获取真机列表 (备选方案)
    private func fetchPhysicalDevicesViaIDB() async -> [DeviceInfo] {
        let result = await runner.runAsync("/usr/local/bin/idb", arguments: ["list-targets", "--json"])
        guard result.isSuccess else { return [] }

        var devices: [DeviceInfo] = []
        let lines = result.stdout.components(separatedBy: "\n")

        for line in lines where !line.isEmpty {
            guard let data = line.data(using: .utf8),
                  let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let udid = json["udid"] as? String,
                  let name = json["name"] as? String,
                  let targetType = json["target_type"] as? String,
                  targetType == "device" else { continue }

            let osVersion = json["os_version"] as? String ?? "Unknown"

            devices.append(DeviceInfo(
                udid: udid,
                name: name,
                deviceType: .physical,
                status: .connected,
                osVersion: osVersion,
                modelName: name,
                screenWidth: 390,
                screenHeight: 844,
                isAvailable: true
            ))
        }
        return devices
    }

    private func parseXCTraceDeviceLine(_ line: String) -> DeviceInfo? {
        // 格式: "iPhone 15 Pro (17.0) (XXXXXXXX-XXXX-XXXX-XXXX-XXXXXXXXXXXX)"
        let pattern = #"^(.+?)\s+\((.+?)\)\s+\(([A-Fa-f0-9-]+)\)$"#
        guard let regex = try? NSRegularExpression(pattern: pattern),
              let match = regex.firstMatch(in: line, range: NSRange(line.startIndex..., in: line)) else {
            return nil
        }

        let name = String(line[Range(match.range(at: 1), in: line)!])
        let osVersion = String(line[Range(match.range(at: 2), in: line)!])
        let udid = String(line[Range(match.range(at: 3), in: line)!])

        return DeviceInfo(
            udid: udid,
            name: name,
            deviceType: .physical,
            status: .connected,
            osVersion: "iOS \(osVersion)",
            modelName: name,
            screenWidth: 390,
            screenHeight: 844,
            isAvailable: true
        )
    }

    // MARK: - 模拟器控制

    /// 启动模拟器
    func bootSimulator(udid: String) async -> Bool {
        logger.info("启动模拟器: \(udid)")
        let result = await runner.simctlAsync(["boot", udid])
        if result.isSuccess {
            // 打开 Simulator.app
            _ = await runner.runAsync("/usr/bin/open", arguments: ["-a", "Simulator"])
            await refreshDevices()
        }
        return result.isSuccess
    }

    /// 关闭模拟器
    func shutdownSimulator(udid: String) async -> Bool {
        logger.info("关闭模拟器: \(udid)")
        let result = await runner.simctlAsync(["shutdown", udid])
        await refreshDevices()
        return result.isSuccess
    }

    // MARK: - 应用管理

    /// 安装应用
    func installApp(udid: String, appPath: String) async -> Bool {
        logger.info("安装应用到设备 \(udid): \(appPath)")
        let result = await runner.simctlAsync(["install", udid, appPath])
        return result.isSuccess
    }

    /// 卸载应用
    func uninstallApp(udid: String, bundleId: String) async -> Bool {
        logger.info("卸载应用: \(bundleId)")
        let result = await runner.simctlAsync(["uninstall", udid, bundleId])
        return result.isSuccess
    }

    /// 启动应用
    func launchApp(udid: String, bundleId: String) async -> Bool {
        logger.info("启动应用: \(bundleId)")
        let result = await runner.simctlAsync(["launch", udid, bundleId])
        return result.isSuccess
    }

    /// 终止应用
    func terminateApp(udid: String, bundleId: String) async -> Bool {
        logger.info("终止应用: \(bundleId)")
        let result = await runner.simctlAsync(["terminate", udid, bundleId])
        return result.isSuccess
    }

    // MARK: - 设备交互

    /// 模拟器点击
    func tap(udid: String, x: Int, y: Int) async -> Bool {
        let result = await runner.simctlAsync(["io", udid, "tap", "\(x)", "\(y)"])
        return result.isSuccess
    }

    /// 模拟器滑动
    func swipe(udid: String, startX: Int, startY: Int, endX: Int, endY: Int, duration: Double = 0.5) async -> Bool {
        let result = await runner.simctlAsync([
            "io", udid, "swipe",
            "\(startX)", "\(startY)", "\(endX)", "\(endY)",
            "--duration", String(format: "%.1f", duration)
        ])
        return result.isSuccess
    }

    /// 长按 (通过 swipe 同一点实现)
    func longPress(udid: String, x: Int, y: Int, duration: Double = 1.0) async -> Bool {
        let result = await runner.simctlAsync([
            "io", udid, "swipe",
            "\(x)", "\(y)", "\(x)", "\(y)",
            "--duration", String(format: "%.1f", duration)
        ])
        return result.isSuccess
    }

    /// Home 键
    func pressHome(udid: String) async -> Bool {
        let result = await runner.simctlAsync(["io", udid, "sendkey", "home"])
        return result.isSuccess
    }

    /// 音量加
    func pressVolumeUp(udid: String) async -> Bool {
        let result = await runner.simctlAsync(["io", udid, "sendkey", "volumeUp"])
        return result.isSuccess
    }

    /// 音量减
    func pressVolumeDown(udid: String) async -> Bool {
        let result = await runner.simctlAsync(["io", udid, "sendkey", "volumeDown"])
        return result.isSuccess
    }

    /// 锁屏
    func lockScreen(udid: String) async -> Bool {
        let result = await runner.simctlAsync(["io", udid, "sendkey", "lock"])
        return result.isSuccess
    }

    /// 摇晃 (Shake gesture)
    func shake(udid: String) async -> Bool {
        // 使用 AppleScript 发送摇晃手势到 Simulator
        let script = "tell application \"Simulator\" to activate\n" +
                     "tell application \"System Events\" to keystroke \"z\" using {control down, command down}"
        let result = await runner.runAsync("/usr/bin/osascript", arguments: ["-e", script])
        return result.isSuccess
    }

    /// 输入文本
    func inputText(udid: String, text: String) async -> Bool {
        let result = await runner.simctlAsync(["io", udid, "sendtext", text])
        return result.isSuccess
    }

    // MARK: - 设备轮询

    func startPolling(interval: TimeInterval = 5.0) {
        stopPolling()
        isPolling = true
        pollTimer = Timer.scheduledTimer(withTimeInterval: interval, repeats: true) { [weak self] _ in
            Task { await self?.refreshDevices() }
        }
        Task { await refreshDevices() }
    }

    func stopPolling() {
        pollTimer?.invalidate()
        pollTimer = nil
        isPolling = false
    }

    // MARK: - 辅助方法

    private func getSimulatorScreenSize(name: String) -> (width: Int, height: Int) {
        for device in CoordinateAdapter.knownResolutions {
            if name.contains(device.name) || device.name.contains(name) {
                return (width: device.width, height: device.height)
            }
        }
        // 默认 iPhone 尺寸
        if name.contains("iPad") { return (width: 820, height: 1180) }
        return (width: 390, height: 844)
    }
}
