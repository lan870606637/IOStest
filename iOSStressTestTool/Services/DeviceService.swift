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
        var physicals: [DeviceInfo] = []
        var seenUDIDs = Set<String>()

        // 方法1: libimobiledevice (idevice_id/ideviceinfo) — 支持所有 iOS 版本 (含 iOS 14 等老系统)
        for device in await fetchPhysicalDevicesViaLibimobiledevice() where !seenUDIDs.contains(device.udid) {
            seenUDIDs.insert(device.udid)
            physicals.append(device)
        }

        // 方法2: xcrun devicectl — iOS 17+ 设备 (CoreDevice 只支持新系统)
        if let devicectlDevices = await fetchPhysicalDevicesViaDevicectl() {
            for device in devicectlDevices where !seenUDIDs.contains(device.udid) {
                seenUDIDs.insert(device.udid)
                physicals.append(device)
            }
        }

        if !physicals.isEmpty {
            return physicals
        }

        // 方法3: xcrun xctrace (兜底)
        logger.warning("devicectl/libimobiledevice 未发现真机，尝试 xctrace")
        let result = await runner.runAsync("/usr/bin/xcrun", arguments: ["xctrace", "list", "devices"])
        guard result.isSuccess else {
            logger.warning("xcrun xctrace 获取真机列表失败，尝试 idb")
            return await fetchPhysicalDevicesViaIDB()
        }

        var fallbackDevices: [DeviceInfo] = []
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
                    fallbackDevices.append(parsed)
                }
            }
        }

        return fallbackDevices
    }

    /// 通过 libimobiledevice 获取真机列表 (方法1, 支持所有 iOS 版本)
    private func fetchPhysicalDevicesViaLibimobiledevice() async -> [DeviceInfo] {
        guard let ideviceID = findTool(named: "idevice_id", in: ["/opt/homebrew/bin", "/usr/local/bin"]),
              let ideviceInfo = findTool(named: "ideviceinfo", in: ["/opt/homebrew/bin", "/usr/local/bin"]) else {
            return []
        }

        let idResult = await runner.runAsync(ideviceID, arguments: ["-l"], timeout: 15)
        guard idResult.isSuccess else { return [] }

        let udids = idResult.stdout
            .components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }

        var devices: [DeviceInfo] = []
        for udid in udids {
            let infoResult = await runner.runAsync(ideviceInfo, arguments: ["-u", udid], timeout: 20)
            guard infoResult.isSuccess else { continue }

            // ideviceinfo 输出为 "Key: Value" 文本行格式
            var info: [String: String] = [:]
            for line in infoResult.stdout.components(separatedBy: .newlines) {
                let parts = line.split(separator: ":", maxSplits: 1).map(String.init)
                guard parts.count == 2 else { continue }
                info[parts[0].trimmingCharacters(in: .whitespaces)] = parts[1].trimmingCharacters(in: .whitespaces)
            }

            let name = info["DeviceName"] ?? "iPhone"
            let version = info["ProductVersion"] ?? "Unknown"
            let productType = info["ProductType"] ?? ""
            let size = CoordinateAdapter.resolution(forProductType: productType) ?? (390, 844)

            devices.append(DeviceInfo(
                udid: udid,
                name: name,
                deviceType: .physical,
                status: .connected,  // usbmuxd 可见即已连接
                osVersion: "iOS \(version)",
                modelName: productType.isEmpty ? name : productType,
                screenWidth: size.width,
                screenHeight: size.height,
                isAvailable: true
            ))
        }

        if !devices.isEmpty {
            logger.info("libimobiledevice 发现 \(devices.count) 台真机: \(devices.map { "\($0.name)(\($0.udid))" }.joined(separator: ", "))")
        }
        return devices
    }

    /// 在候选目录中查找可执行工具
    private func findTool(named name: String, in dirs: [String]) -> String? {
        for dir in dirs {
            let path = dir + "/" + name
            if FileManager.default.isExecutableFile(atPath: path) {
                return path
            }
        }
        return nil
    }

    /// 通过 devicectl 获取真机列表 (方法1)
    private func fetchPhysicalDevicesViaDevicectl() async -> [DeviceInfo]? {
        let result = await runner.runAsync(
            "/usr/bin/xcrun",
            arguments: ["devicectl", "list", "devices", "--json-output", "-"],
            timeout: 60
        )
        guard result.isSuccess,
              let data = result.stdout.data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let resultDict = json["result"] as? [String: Any],
              let deviceList = resultDict["devices"] as? [[String: Any]] else {
            logger.warning("devicectl 输出解析失败: \(result.stderr.prefix(200))")
            return nil
        }

        var physicals: [DeviceInfo] = []
        for device in deviceList {
            guard let hardware = device["hardwareProperties"] as? [String: Any],
                  let props = device["deviceProperties"] as? [String: Any],
                  let connection = device["connectionProperties"] as? [String: Any] else { continue }

            // 只保留有真实 UDID 的条目 (iOS 14 等老设备在 devicectl 中只有 identifier、无 UDID，
            // 交由 libimobiledevice 路径发现)
            guard let udid = hardware["udid"] as? String else { continue }

            let name = (props["name"] as? String) ?? (hardware["marketingName"] as? String) ?? "Unknown"
            let marketingName = hardware["marketingName"] as? String ?? name
            let osVersion = props["osVersionNumber"] as? String ?? "Unknown"
            let tunnelState = connection["tunnelState"] as? String ?? ""
            let productType = hardware["productType"] as? String ?? ""

            let size = CoordinateAdapter.resolution(forProductType: productType) ?? (390, 844)

            physicals.append(DeviceInfo(
                udid: udid,
                name: name,
                deviceType: .physical,
                status: tunnelState == "connected" ? .connected : .disconnected,
                osVersion: "iOS \(osVersion)",
                modelName: marketingName,
                screenWidth: size.width,
                screenHeight: size.height,
                isAvailable: true,
                coreDeviceID: device["identifier"] as? String
            ))
        }

        if !physicals.isEmpty {
            logger.info("devicectl 发现 \(physicals.count) 台真机: \(physicals.map { "\($0.name)(\($0.udid))" }.joined(separator: ", "))")
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
        if isPhysicalDevice(udid) {
            // simctl 不支持真机；真机走 go-ios install（免签名，不需要 WDA）
            return await goIOS.installApp(udid: udid, path: appPath)
        }
        let result = await runner.simctlAsync(["install", udid, appPath])
        return result.isSuccess
    }

    /// 卸载应用
    func uninstallApp(udid: String, bundleId: String) async -> Bool {
        logger.info("卸载应用: \(bundleId)")
        if isPhysicalDevice(udid) {
            return await goIOS.uninstallApp(udid: udid, bundleID: bundleId)
        }
        let result = await runner.simctlAsync(["uninstall", udid, bundleId])
        return result.isSuccess
    }

    /// 启动应用
    func launchApp(udid: String, bundleId: String) async -> Bool {
        logger.info("启动应用: \(bundleId)")
        if isPhysicalDevice(udid) {
            // simctl 不支持真机；真机走 go-ios launch（免签名）
            return await goIOS.launchApp(udid: udid, bundleID: bundleId)
        }
        let result = await runner.simctlAsync(["launch", udid, bundleId])
        return result.isSuccess
    }

    /// 终止应用
    func terminateApp(udid: String, bundleId: String) async -> Bool {
        logger.info("终止应用: \(bundleId)")
        if isPhysicalDevice(udid) {
            // simctl 不支持真机；真机走 go-ios kill（免签名）
            return await goIOS.terminateApp(udid: udid, bundleID: bundleId)
        }
        let result = await runner.simctlAsync(["terminate", udid, bundleId])
        return result.isSuccess
    }

    // MARK: - 设备交互

    /// 模拟器点击
    func tap(udid: String, x: Int, y: Int) async -> Bool {
        if isPhysicalDevice(udid) {
            return await physicalTap(udid: udid, x: x, y: y)
        }
        let result = await runner.simctlAsync(["io", udid, "tap", "\(x)", "\(y)"])
        return result.isSuccess
    }

    /// 模拟器滑动
    func swipe(udid: String, startX: Int, startY: Int, endX: Int, endY: Int, duration: Double = 0.5) async -> Bool {
        if isPhysicalDevice(udid) {
            return await physicalSwipe(
                udid: udid,
                startX: startX, startY: startY,
                endX: endX, endY: endY,
                duration: duration
            )
        }
        let result = await runner.simctlAsync([
            "io", udid, "swipe",
            "\(startX)", "\(startY)", "\(endX)", "\(endY)",
            "--duration", String(format: "%.1f", duration)
        ])
        return result.isSuccess
    }

    /// 长按 (通过 swipe 同一点实现)
    func longPress(udid: String, x: Int, y: Int, duration: Double = 1.0) async -> Bool {
        if isPhysicalDevice(udid) {
            return await physicalLongPress(udid: udid, x: x, y: y, duration: duration)
        }
        let result = await runner.simctlAsync([
            "io", udid, "swipe",
            "\(x)", "\(y)", "\(x)", "\(y)",
            "--duration", String(format: "%.1f", duration)
        ])
        return result.isSuccess
    }

    /// Home 键
    func pressHome(udid: String) async -> Bool {
        if isPhysicalDevice(udid) {
            return await physicalPressButton(udid: udid, button: "home")
        }
        let result = await runner.simctlAsync(["io", udid, "sendkey", "home"])
        return result.isSuccess
    }

    /// 音量加
    func pressVolumeUp(udid: String) async -> Bool {
        if isPhysicalDevice(udid) {
            return await physicalPressButton(udid: udid, button: "volumeUp")
        }
        let result = await runner.simctlAsync(["io", udid, "sendkey", "volumeUp"])
        return result.isSuccess
    }

    /// 音量减
    func pressVolumeDown(udid: String) async -> Bool {
        if isPhysicalDevice(udid) {
            return await physicalPressButton(udid: udid, button: "volumeDown")
        }
        let result = await runner.simctlAsync(["io", udid, "sendkey", "volumeDown"])
        return result.isSuccess
    }

    /// 锁屏
    func lockScreen(udid: String) async -> Bool {
        if isPhysicalDevice(udid) {
            return await physicalPressButton(udid: udid, button: "lock")
        }
        let result = await runner.simctlAsync(["io", udid, "sendkey", "lock"])
        return result.isSuccess
    }

    /// 摇晃 (Shake gesture)
    func shake(udid: String) async -> Bool {
        if isPhysicalDevice(udid) {
            logger.warning("真机暂不支持摇晃手势 (go-ios/idb 均无 shake 命令)")
            return false
        }
        // 使用 AppleScript 发送摇晃手势到 Simulator
        let script = "tell application \"Simulator\" to activate\n" +
                     "tell application \"System Events\" to keystroke \"z\" using {control down, command down}"
        let result = await runner.runAsync("/usr/bin/osascript", arguments: ["-e", script])
        return result.isSuccess
    }

    /// 输入文本
    func inputText(udid: String, text: String) async -> Bool {
        if isPhysicalDevice(udid) {
            return await physicalInputText(udid: udid, text: text)
        }
        let result = await runner.simctlAsync(["io", udid, "sendtext", text])
        return result.isSuccess
    }

    // MARK: - 真机控制
    //
    // 实现顺序：go-ios 优先，idb 兜底。
    //
    // 注意能力边界（go-ios 分三档）：
    //  - 免签名：launch / kill / install / uninstall / screenshot / tunnel
    //  - 需签名：ui tap|swipe|longpress|type|button —— 需要设备上已装好
    //    已签名的 WDA 或 DeviceKit，否则会报 "no UI automation backend reachable"
    //  - 不支持：shake

    /// 判断 udid 是否为真机
    private func isPhysicalDevice(_ udid: String) -> Bool {
        devices.contains { $0.udid == udid && $0.deviceType == .physical }
    }

    /// go-ios 客户端
    private var goIOS: GoIOSClient { GoIOSClient.shared }

    /// 真机点击：go-ios → idb
    private func physicalTap(udid: String, x: Int, y: Int) async -> Bool {
        if goIOS.isAvailable, await goIOS.tap(udid: udid, x: x, y: y) {
            return true
        }
        return await idbUI(udid, ["ui", "tap", "\(x)", "\(y)"])
    }

    /// 真机滑动：go-ios → idb
    private func physicalSwipe(udid: String,
                               startX: Int, startY: Int,
                               endX: Int, endY: Int,
                               duration: Double) async -> Bool {
        if goIOS.isAvailable,
           await goIOS.swipe(udid: udid, startX: startX, startY: startY,
                             endX: endX, endY: endY, duration: duration) {
            return true
        }
        return await idbUI(udid, [
            "ui", "swipe",
            "\(startX)", "\(startY)", "\(endX)", "\(endY)",
            "--duration", String(format: "%.1f", duration)
        ])
    }

    /// 真机长按：go-ios → idb
    private func physicalLongPress(udid: String, x: Int, y: Int, duration: Double) async -> Bool {
        if goIOS.isAvailable,
           await goIOS.longPress(udid: udid, x: x, y: y, duration: duration) {
            return true
        }
        return await idbUI(udid, [
            "ui", "tap", "\(x)", "\(y)",
            "--duration", String(format: "%.1f", duration)
        ])
    }

    /// 真机按键：go-ios → idb
    /// go-ios 的按钮名是小写驼峰/单词（home / lock / volumeUp / volumeDown），
    /// idb 用的是大写常量（HOME / LOCK / VOLUME_UP / VOLUME_DOWN），此处做映射。
    private func physicalPressButton(udid: String, button: String) async -> Bool {
        if goIOS.isAvailable,
           await goIOS.pressButton(udid: udid, button: button) {
            return true
        }
        let idbButton: String
        switch button {
        case "home": idbButton = "HOME"
        case "lock": idbButton = "LOCK"
        case "volumeUp": idbButton = "VOLUME_UP"
        case "volumeDown": idbButton = "VOLUME_DOWN"
        default: idbButton = button.uppercased()
        }
        return await idbUI(udid, ["ui", "button", idbButton])
    }

    /// 真机输入文字：go-ios → idb
    private func physicalInputText(udid: String, text: String) async -> Bool {
        if goIOS.isAvailable, await goIOS.typeText(udid: udid, text: text) {
            return true
        }
        return await idbUI(udid, ["ui", "text", text])
    }

    /// 查找 idb 客户端 (需要 idb_companion 已安装并在 PATH 中)
    private var idbPath: String? {
        for dir in ["/opt/homebrew/bin", "/usr/local/bin"] {
            let path = dir + "/idb"
            if FileManager.default.isExecutableFile(atPath: path) { return path }
        }
        return nil
    }

    /// 真机执行 idb ui 命令（go-ios UI 后端不可用时的兜底）
    private func idbUI(_ udid: String, _ args: [String]) async -> Bool {
        guard let idb = idbPath else {
            logger.error("""
                真机操作没有可用后端。
                go-ios 的 UI 控制需要已签名的 WDA 或 DeviceKit：
                  ios ui install wda --p12file=<证书> --profile=<描述文件>
                idb 兜底方案需要 idb_companion（该 formula 已从 Homebrew 下架）
                """)
            return false
        }
        let result = await runner.runAsync(idb, arguments: args + ["--udid", udid], timeout: 60)
        if !result.isSuccess {
            logger.warning("idb 操作失败 (\(args.joined(separator: " "))): \(result.stderr.prefix(300))")
        }
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
