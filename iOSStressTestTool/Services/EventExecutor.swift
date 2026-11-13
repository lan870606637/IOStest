import Foundation
import AppKit

// MARK: - 执行进度回调
struct ExecutionProgress {
    let taskName: String
    let currentLoop: Int
    let totalLoops: Int
    let currentEventIndex: Int
    let totalEvents: Int
    let currentEvent: TestEvent
    let status: EventStatus
    let message: String
}

// MARK: - 事件执行器
/// 核心事件执行引擎，负责按顺序执行测试事件
@MainActor
final class EventExecutor: ObservableObject {
    static let shared = EventExecutor()

    @Published var isExecuting = false
    @Published var currentProgress: ExecutionProgress?
    @Published var shouldStop = false

    private let deviceService = DeviceService.shared
    private let screenshotService = ScreenshotService.shared
    private let imageEngine = ImageRecognitionEngine.shared
    private let ocrEngine = OCREngine.shared
    private let logger = Logger.shared
    private let reportGenerator = ReportGenerator.shared

    /// 新的自动化后端（Appium）。失败时回退到 DeviceService 的 CLI 实现。
    private let backend: AutomationBackend = AppiumBackend()
    /// 记录每个事件实际使用的策略（按事件 id；@MainActor 串行访问）
    private var strategyTrace: [UUID: String] = [:]
    /// 记录截图事件保存的文件路径
    private var screenshotTrace: [UUID: String] = [:]
    /// 当前任务的截图子文件夹（任务名_执行时间）
    private var currentTaskFolder: String?
    /// 当前循环序号，用于截图文件名前缀
    private var currentLoopIndex = 1

    var onProgress: ((ExecutionProgress) -> Void)?
    var onEventComplete: ((TestEvent, EventStatus, String?) -> Void)?

    private init() {}

    // MARK: - 任务执行

    /// 执行整个测试任务
    func executeTask(_ task: TestTask, deviceUDID: String) async {
        guard !isExecuting else {
            logger.warning("已有任务在执行中")
            return
        }

        let runStamp = DateFormatter.fileNameFormatter.string(from: Date())
        currentTaskFolder = "\(Self.sanitizeFolderName(task.name))_\(runStamp)"
        currentLoopIndex = 1
        defer {
            currentTaskFolder = nil
            currentLoopIndex = 1
        }

        await MainActor.run {
            isExecuting = true
            shouldStop = false
        }

        let device = deviceService.devices.first { $0.udid == deviceUDID }
        let deviceName = device?.name ?? deviceUDID

        // 提前建好自动化会话，避免第一条事件等 30 秒
        let bundleId = task.events.compactMap { $0.bundleIdentifier }.first
        let platformVersion = device?.osVersion.replacingOccurrences(of: "iOS ", with: "")
        do {
            try await backend.ensureSession(udid: deviceUDID,
                                            bundleId: bundleId,
                                            platformVersion: platformVersion)
            logger.info("自动化会话就绪 (Appium)")
        } catch {
            logger.error("创建自动化会话失败，输入将回退到 CLI 后端: \(error.localizedDescription)")
        }

        // 开始报告
        reportGenerator.startReport(taskName: task.name, deviceUDID: deviceUDID, deviceName: deviceName)

        logger.info("开始执行任务: \(task.name), 设备: \(deviceName), 循环次数: \(task.loopCount)")

        for loopIndex in 1...task.loopCount {
            currentLoopIndex = loopIndex
            guard !shouldStop else {
                logger.info("任务被手动停止")
                break
            }

            reportGenerator.startLoop(index: loopIndex)
            logger.info("--- 循环 \(loopIndex)/\(task.loopCount) ---")

            for (eventIndex, event) in task.enabledEvents.enumerated() {
                guard !shouldStop else { break }

                let progress = ExecutionProgress(
                    taskName: task.name,
                    currentLoop: loopIndex,
                    totalLoops: task.loopCount,
                    currentEventIndex: eventIndex + 1,
                    totalEvents: task.enabledEvents.count,
                    currentEvent: event,
                    status: .running,
                    message: "执行: \(event.type.displayName) - \(event.remark)"
                )
                await MainActor.run { self.currentProgress = progress }
                onProgress?(progress)

                let (status, errorMsg) = await executeEvent(event, deviceUDID: deviceUDID)

                onEventComplete?(event, status, errorMsg)

                if status == .failed {
                    logger.error("事件执行失败: \(event.type.displayName) - \(errorMsg ?? "")")
                }

                // 事件间延迟
                if event.delay > 0 {
                    try? await Task.sleep(nanoseconds: UInt64(event.delay * 1_000_000_000))
                }
            }

            reportGenerator.endLoop()
        }

        // 完成报告
        let report = reportGenerator.finishReport()
        logger.info("任务执行完成: \(task.name), 报告ID: \(report?.id.uuidString ?? "N/A")")

        await MainActor.run {
            isExecuting = false
            currentProgress = nil
        }
    }

    /// 停止执行
    func stop() {
        shouldStop = true
        logger.info("请求停止任务执行")
    }

    // MARK: - 单事件执行

    /// 单步执行：先确保自动化会话，再执行一个事件。
    func executeSingleEvent(_ event: TestEvent,
                            deviceUDID: String,
                            bundleId: String?) async -> (EventStatus, String?) {
        let device = deviceService.devices.first { $0.udid == deviceUDID }
        let platformVersion = device?.osVersion.replacingOccurrences(of: "iOS ", with: "")
        do {
            try await backend.ensureSession(udid: deviceUDID,
                                            bundleId: bundleId,
                                            platformVersion: platformVersion)
        } catch {
            return (.failed, "建立自动化会话失败: \(error.localizedDescription)")
        }
        return await executeEvent(event, deviceUDID: deviceUDID)
    }

    /// 执行单个事件，返回 (状态, 错误消息)
    func executeEvent(_ event: TestEvent, deviceUDID: String) async -> (EventStatus, String?) {
        let eventReport = EventReportData(event: event)
        reportGenerator.startEvent(eventReport)

        if let bundleId = event.bundleIdentifier, !bundleId.isEmpty {
            try? await backend.ensureSession(udid: deviceUDID,
                                             bundleId: bundleId,
                                             platformVersion: nil)
        }

        let result: (EventStatus, String?)

        switch event.type {
        case .click:
            result = await executeClick(event, deviceUDID: deviceUDID)
        case .doubleClick:
            result = await executeDoubleClick(event, deviceUDID: deviceUDID)
        case .longPress:
            result = await executeLongPress(event, deviceUDID: deviceUDID)
        case .swipe:
            result = await executeSwipe(event, deviceUDID: deviceUDID)
        case .imageRecognitionClick:
            result = await executeImageRecognitionClick(event, deviceUDID: deviceUDID)
        case .ocrTextClick:
            result = await executeOCRTextClick(event, deviceUDID: deviceUDID)
        case .popupButton:
            result = await executePopupButton(event, deviceUDID: deviceUDID)
        case .screenshot:
            result = await executeScreenshot(event, deviceUDID: deviceUDID)
        case .compareScreenshot:
            result = await executeCompareScreenshot(event, deviceUDID: deviceUDID)
        case .killApp:
            result = await executeKillApp(event, deviceUDID: deviceUDID)
        case .launchApp:
            result = await executeLaunchApp(event, deviceUDID: deviceUDID)
        case .homeButton:
            result = await executeHardwareButton(.homeButton, deviceUDID: deviceUDID)
        case .volumeUp:
            result = await executeHardwareButton(.volumeUp, deviceUDID: deviceUDID)
        case .volumeDown:
            result = await executeHardwareButton(.volumeDown, deviceUDID: deviceUDID)
        case .lockScreen:
            result = await executeHardwareButton(.lockScreen, deviceUDID: deviceUDID)
        case .shake:
            result = await executeHardwareButton(.shake, deviceUDID: deviceUDID)
        case .custom:
            result = await executeCustomCommand(event, deviceUDID: deviceUDID)
        case .assertion:
            result = await executeAssertion(event, deviceUDID: deviceUDID)
        case .eventGroup:
            result = await executeEventGroup(event, deviceUDID: deviceUDID)
        }

        reportGenerator.endEvent(status: result.0,
                                 errorMessage: result.1,
                                 screenshotPath: takeScreenshotPath(event),
                                 strategy: takeStrategy(event))
        return result
    }

    // MARK: - 后端路由（Appium 优先，CLI 兜底）

    private func recordStrategy(_ event: TestEvent, _ strategy: String) {
        strategyTrace[event.id] = strategy
    }

    private func takeStrategy(_ event: TestEvent) -> String? {
        strategyTrace.removeValue(forKey: event.id)
    }

    private func recordScreenshotPath(_ event: TestEvent, _ path: String) {
        screenshotTrace[event.id] = path
    }

    private func takeScreenshotPath(_ event: TestEvent) -> String? {
        screenshotTrace.removeValue(forKey: event.id)
    }

    private static func sanitizeFolderName(_ name: String) -> String {
        let invalid = CharacterSet(charactersIn: "/\\:*?\"<>|")
        let cleaned = name
            .components(separatedBy: invalid)
            .joined(separator: "_")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        if cleaned.isEmpty || cleaned == "." || cleaned == ".." {
            return "未命名任务"
        }
        return String(cleaned.prefix(80))
    }

    /// 轮询等待控件出现；超时返回 nil，会话错误继续抛出。
    private func waitForElement(udid: String, locator: Locator) async throws -> ElementHandle? {
        let timeout = max(locator.timeout, 0.2)
        let deadline = Date().addingTimeInterval(timeout)
        repeat {
            if let element = try await backend.findElement(udid: udid, locator: locator) {
                return element
            }
            try? await Task.sleep(nanoseconds: 250_000_000)
        } while Date() < deadline
        return nil
    }

    private func tap(udid: String, x: Int, y: Int) async -> Bool {
        do {
            try await backend.tap(udid: udid, x: x, y: y)
            return true
        } catch {
            logger.warning("Appium 点击失败，回退 CLI: \(error.localizedDescription)")
            return await deviceService.tap(udid: udid, x: x, y: y)
        }
    }

    private func doubleTap(udid: String, x: Int, y: Int) async -> Bool {
        do {
            try await backend.doubleTap(udid: udid, x: x, y: y)
            return true
        } catch {
            logger.warning("Appium 双击失败，回退 CLI: \(error.localizedDescription)")
            let first = await deviceService.tap(udid: udid, x: x, y: y)
            try? await Task.sleep(nanoseconds: 100_000_000)
            let second = await deviceService.tap(udid: udid, x: x, y: y)
            return first && second
        }
    }

    private func longPress(udid: String, x: Int, y: Int, duration: TimeInterval) async -> Bool {
        do {
            try await backend.longPress(udid: udid, x: x, y: y, duration: duration)
            return true
        } catch {
            logger.warning("Appium 长按失败，回退 CLI: \(error.localizedDescription)")
            return await deviceService.longPress(udid: udid, x: x, y: y, duration: duration)
        }
    }

    private func swipe(udid: String,
                       fromX: Int, fromY: Int,
                       toX: Int, toY: Int,
                       duration: TimeInterval) async -> Bool {
        do {
            try await backend.swipe(udid: udid,
                                    fromX: fromX, fromY: fromY,
                                    toX: toX, toY: toY,
                                    duration: duration)
            return true
        } catch {
            logger.warning("Appium 滑动失败，回退 CLI: \(error.localizedDescription)")
            return await deviceService.swipe(udid: udid,
                                             startX: fromX, startY: fromY,
                                             endX: toX, endY: toY,
                                             duration: duration)
        }
    }

    private func press(_ button: HardwareButton, udid: String) async -> Bool {
        do {
            try await backend.pressButton(udid: udid, button: button)
            return true
        } catch {
            logger.warning("Appium 按键失败，回退 CLI: \(error.localizedDescription)")
            switch button {
            case .home: return await deviceService.pressHome(udid: udid)
            case .lock: return await deviceService.lockScreen(udid: udid)
            case .volumeUp: return await deviceService.pressVolumeUp(udid: udid)
            case .volumeDown: return await deviceService.pressVolumeDown(udid: udid)
            }
        }
    }

    private func captureScreenshot(device: DeviceInfo) async -> NSImage? {
        if let data = try? await backend.screenshot(udid: device.udid),
           let image = NSImage(data: data) {
            return image
        }
        return await screenshotService.captureScreenshot(deviceUDID: device.udid,
                                                         deviceType: device.deviceType)
    }

    // MARK: - 具体事件执行

    private func executeClick(_ event: TestEvent, deviceUDID: String) async -> (EventStatus, String?) {
        if let locator = event.locator, locator.strategy != .point {
            do {
                if let element = try await waitForElement(udid: deviceUDID, locator: locator) {
                    try await backend.click(udid: deviceUDID, element: element)
                    recordStrategy(event, "控件 \(locator.summary)")
                    return (.success, nil)
                }
                logger.warning("控件未找到，回退坐标: \(locator.summary)")
            } catch {
                logger.warning("控件定位失败，回退坐标: \(error.localizedDescription)")
            }
        }

        guard let x = event.x, let y = event.y else {
            return (.failed, event.locator == nil ? "点击坐标未设置" : "控件未找到且未设置坐标")
        }
        if await tap(udid: deviceUDID, x: x, y: y) {
            recordStrategy(event, "坐标 (\(x), \(y))")
            return (.success, nil)
        }
        return (.failed, "点击执行失败")
    }

    private func executeDoubleClick(_ event: TestEvent, deviceUDID: String) async -> (EventStatus, String?) {
        if let locator = event.locator, locator.strategy != .point {
            do {
                if let element = try await waitForElement(udid: deviceUDID, locator: locator) {
                    let rect = try await backend.rect(udid: deviceUDID, element: element)
                    let x = Int(rect.midX), y = Int(rect.midY)
                    if await doubleTap(udid: deviceUDID, x: x, y: y) {
                        recordStrategy(event, "控件 \(locator.summary) 中心 (\(x), \(y))")
                        return (.success, nil)
                    }
                }
            } catch {
                logger.warning("双击控件定位失败，回退坐标: \(error.localizedDescription)")
            }
        }

        guard let x = event.x, let y = event.y else {
            return (.failed, event.locator == nil ? "双击坐标未设置" : "控件未找到且未设置坐标")
        }
        if await doubleTap(udid: deviceUDID, x: x, y: y) {
            recordStrategy(event, "坐标 (\(x), \(y))")
            return (.success, nil)
        }
        return (.failed, "双击执行失败")
    }

    private func executeLongPress(_ event: TestEvent, deviceUDID: String) async -> (EventStatus, String?) {
        if let locator = event.locator, locator.strategy != .point {
            do {
                if let element = try await waitForElement(udid: deviceUDID, locator: locator) {
                    let rect = try await backend.rect(udid: deviceUDID, element: element)
                    let x = Int(rect.midX), y = Int(rect.midY)
                    if await longPress(udid: deviceUDID, x: x, y: y, duration: event.pressDuration) {
                        recordStrategy(event, "控件 \(locator.summary) 中心 (\(x), \(y))")
                        return (.success, nil)
                    }
                }
            } catch {
                logger.warning("长按控件定位失败，回退坐标: \(error.localizedDescription)")
            }
        }

        guard let x = event.x, let y = event.y else {
            return (.failed, event.locator == nil ? "长按坐标未设置" : "控件未找到且未设置坐标")
        }
        if await longPress(udid: deviceUDID, x: x, y: y, duration: event.pressDuration) {
            recordStrategy(event, "坐标 (\(x), \(y))")
            return (.success, nil)
        }
        return (.failed, "长按执行失败")
    }

    private func executeSwipe(_ event: TestEvent, deviceUDID: String) async -> (EventStatus, String?) {
        guard let sx = event.startX, let sy = event.startY,
              let ex = event.endX, let ey = event.endY else {
            return (.failed, "滑动坐标未设置")
        }
        if await swipe(udid: deviceUDID,
                       fromX: sx, fromY: sy,
                       toX: ex, toY: ey,
                       duration: event.swipeDuration) {
            recordStrategy(event, "坐标滑动 (\(sx),\(sy))→(\(ex),\(ey))")
            return (.success, nil)
        }
        return (.failed, "滑动执行失败")
    }

    private func executeImageRecognitionClick(_ event: TestEvent, deviceUDID: String) async -> (EventStatus, String?) {
        guard let templateName = event.templateName else {
            return (.failed, "未指定模板图像")
        }

        let templateDir = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
            .appendingPathComponent("iOSStressTestTool/templates")
        let templatePath = templateDir.appendingPathComponent(templateName).path

        guard let device = deviceService.devices.first(where: { $0.udid == deviceUDID }) else {
            return (.failed, "设备未找到")
        }

        // 截图
        guard let screenshot = await captureScreenshot(device: device) else {
            return (.failed, "截图失败")
        }

        // 图像识别
        let threshold = Double(event.similarity) / 100.0
        let result = await imageEngine.findTemplate(templatePath: templatePath, in: screenshot, similarityThreshold: threshold)

        guard result.found, let center = result.centerPoint else {
            return (.failed, "未识别到模板图像 (confidence: \(String(format: "%.2f", result.confidence)))")
        }

        // 转换坐标并点击
        let coords = imageEngine.normalizedToDeviceCoordinates(
            point: center,
            deviceWidth: device.screenWidth,
            deviceHeight: device.screenHeight
        )

        if await tap(udid: deviceUDID, x: coords.x, y: coords.y) {
            recordStrategy(event, "图像识别 (\(coords.x), \(coords.y))")
            return (.success, nil)
        }
        return (.failed, "图像识别后点击失败")
    }

    private func executeOCRTextClick(_ event: TestEvent, deviceUDID: String) async -> (EventStatus, String?) {
        guard let targetText = event.targetText, !targetText.isEmpty else {
            return (.failed, "未指定目标文字")
        }

        guard let device = deviceService.devices.first(where: { $0.udid == deviceUDID }) else {
            return (.failed, "设备未找到")
        }

        guard let screenshot = await captureScreenshot(device: device) else {
            return (.failed, "截图失败")
        }

        let result = await ocrEngine.findText(targetText, in: screenshot)

        guard result.found, let bbox = result.boundingBox else {
            return (.failed, "未找到文字: \(targetText)")
        }

        let coords = ocrEngine.visionToScreenCoordinates(
            boundingBox: bbox,
            screenWidth: device.screenWidth,
            screenHeight: device.screenHeight
        )

        if await tap(udid: deviceUDID, x: coords.x, y: coords.y) {
            recordStrategy(event, "OCR (\(coords.x), \(coords.y))")
            return (.success, nil)
        }
        return (.failed, "OCR 识别后点击失败")
    }

    /// 按文案循环查找并点击弹窗按钮：App 内控件 → 系统弹窗，直到超时。
    private func executePopupButton(_ event: TestEvent, deviceUDID: String) async -> (EventStatus, String?) {
        let rawText = event.popupButtonText ?? event.targetText ?? ""
        let text = rawText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else {
            return (.failed, "未指定弹窗按钮文案")
        }

        let timeout = max(event.popupTimeout ?? 15.0, 0.5)
        let interval = max(event.popupInterval ?? 0.5, 0.1)
        let deadline = Date().addingTimeInterval(timeout)
        var lastError: String?

        do {
            try await backend.ensureSession(udid: deviceUDID, bundleId: nil, platformVersion: nil)
        } catch {
            return (.failed, "无法建立自动化会话: \(error.localizedDescription)")
        }

        let escaped = text
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
        let locator = Locator(strategy: .predicate,
                              value: "label == \"\(escaped)\" OR name == \"\(escaped)\"",
                              timeout: interval)

        while Date() < deadline {
            // 1. App 内弹窗按钮
            if let element = try? await backend.findElement(udid: deviceUDID, locator: locator) {
                do {
                    try await backend.click(udid: deviceUDID, element: element)
                    recordStrategy(event, "弹窗按钮 \(text)（App 内）")
                    return (.success, nil)
                } catch {
                    lastError = error.localizedDescription
                }
            }

            // 2. 系统弹窗（SpringBoard / 权限弹窗）
            do {
                let buttons = try await backend.alertButtons(udid: deviceUDID)
                if let matched = buttons.first(where: { $0 == text })
                    ?? buttons.first(where: { $0.contains(text) }) {
                    try await backend.acceptAlert(udid: deviceUDID, buttonLabel: matched)
                    recordStrategy(event, "弹窗按钮 \(matched)（系统弹窗）")
                    return (.success, nil)
                }
            } catch {
                lastError = error.localizedDescription
            }

            try? await Task.sleep(nanoseconds: UInt64(interval * 1_000_000_000))
        }

        let suffix = lastError.map { "，最后错误: \($0)" } ?? ""
        return (.failed, "弹窗按钮 '\(text)' 在 \(String(format: "%.1f", timeout)) 秒内未出现\(suffix)")
    }

    private func executeScreenshot(_ event: TestEvent, deviceUDID: String) async -> (EventStatus, String?) {
        guard let device = deviceService.devices.first(where: { $0.udid == deviceUDID }) else {
            return (.failed, "设备未找到")
        }
        screenshotService.invalidateCache(for: deviceUDID)
        guard let screenshot = await captureScreenshot(device: device) else {
            return (.failed, "截图失败")
        }
        let base = event.remark.isEmpty ? "screenshot" : event.remark
        let name = "\(currentLoopIndex)_\(Self.sanitizeFolderName(base))"
        let subfolder = currentTaskFolder ?? "未分组"
        if let path = screenshotService.saveScreenshot(screenshot, name: name, subfolder: subfolder) {
            recordScreenshotPath(event, path)
        }
        return (.success, nil)
    }

    private func executeCompareScreenshot(_ event: TestEvent, deviceUDID: String) async -> (EventStatus, String?) {
        guard let templateName = event.templateName else {
            return (.failed, "未指定对比模板")
        }
        guard let device = deviceService.devices.first(where: { $0.udid == deviceUDID }) else {
            return (.failed, "设备未找到")
        }

        screenshotService.invalidateCache(for: deviceUDID)
        guard let screenshot = await captureScreenshot(device: device),
              let cgScreenshot = screenshot.cgImage(forProposedRect: nil, context: nil, hints: nil) else {
            return (.failed, "截图失败")
        }

        guard let templateCG = ImageCompareUtils.shared.loadImage(from: templateName) else {
            return (.failed, "无法加载对比模板")
        }

        let result = ImageCompareUtils.shared.compare(image1: templateCG, image2: cgScreenshot)
        let threshold = Double(event.similarity) / 100.0

        if result.similarity >= threshold {
            return (.success, nil)
        } else {
            return (.failed, "截图对比不匹配 (相似度: \(String(format: "%.1f%%", result.similarity * 100)))")
        }
    }

    private func executeKillApp(_ event: TestEvent, deviceUDID: String) async -> (EventStatus, String?) {
        guard let bundleId = event.bundleIdentifier, !bundleId.isEmpty else {
            return (.failed, "未指定应用 Bundle ID")
        }
        do {
            try await backend.terminateApp(udid: deviceUDID, bundleId: bundleId)
            recordStrategy(event, "Appium terminateApp")
            return (.success, nil)
        } catch {
            logger.warning("Appium 终止 App 失败，回退 CLI: \(error.localizedDescription)")
        }
        let success = await deviceService.terminateApp(udid: deviceUDID, bundleId: bundleId)
        if success { recordStrategy(event, "CLI terminateApp") }
        return success ? (.success, nil) : (.failed, "终止应用失败")
    }

    private func executeLaunchApp(_ event: TestEvent, deviceUDID: String) async -> (EventStatus, String?) {
        guard let bundleId = event.bundleIdentifier, !bundleId.isEmpty else {
            return (.failed, "未指定应用 Bundle ID")
        }
        do {
            try await backend.launchApp(udid: deviceUDID, bundleId: bundleId)
            recordStrategy(event, "Appium launchApp")
            return (.success, nil)
        } catch {
            logger.warning("Appium 启动 App 失败，回退 CLI: \(error.localizedDescription)")
        }
        let success = await deviceService.launchApp(udid: deviceUDID, bundleId: bundleId)
        if success { recordStrategy(event, "CLI launchApp") }
        return success ? (.success, nil) : (.failed, "启动应用失败")
    }

    private func executeHardwareButton(_ type: EventType, deviceUDID: String) async -> (EventStatus, String?) {
        let success: Bool
        switch type {
        case .homeButton: success = await press(.home, udid: deviceUDID)
        case .volumeUp: success = await press(.volumeUp, udid: deviceUDID)
        case .volumeDown: success = await press(.volumeDown, udid: deviceUDID)
        case .lockScreen: success = await press(.lock, udid: deviceUDID)
        case .shake: success = await deviceService.shake(udid: deviceUDID)
        default: return (.failed, "未知硬件按钮")
        }
        return success ? (.success, nil) : (.failed, "\(type.displayName) 执行失败")
    }

    private func executeCustomCommand(_ event: TestEvent, deviceUDID: String) async -> (EventStatus, String?) {
        guard let command = event.customCommand, !command.isEmpty else {
            return (.failed, "未指定自定义命令")
        }
        let result = await ProcessRunner.shared.runAsync("/bin/bash", arguments: ["-c", command])
        return result.isSuccess ? (.success, nil) : (.failed, "命令执行失败: \(result.stderr)")
    }

    private func executeAssertion(_ event: TestEvent, deviceUDID: String) async -> (EventStatus, String?) {
        guard let assertType = event.assertType,
              let target = event.assertTarget, !target.isEmpty else {
            return (.failed, "断言参数不完整")
        }

        guard let device = deviceService.devices.first(where: { $0.udid == deviceUDID }) else {
            return (.failed, "设备未找到")
        }

        guard let screenshot = await captureScreenshot(device: device) else {
            return (.failed, "断言截图失败")
        }

        switch assertType {
        case .assertText:
            let result = await ocrEngine.findText(target, in: screenshot)
            return result.found ? (.success, nil) : (.failed, "断言失败: 未找到文字 '\(target)'")

        case .assertImage:
            let result = await imageEngine.findTemplate(
                templatePath: target, in: screenshot,
                similarityThreshold: Double(event.similarity) / 100.0
            )
            return result.found ? (.success, nil) : (.failed, "断言失败: 未找到匹配图像")

        case .assertElement:
            // 优先用控件定位断言；没有 locator 时降级 OCR
            if let locator = event.locator, locator.strategy != .point {
                do {
                    if try await waitForElement(udid: deviceUDID, locator: locator) != nil {
                        recordStrategy(event, "控件断言 \(locator.summary)")
                        return (.success, nil)
                    }
                    return (.failed, "断言失败: 未找到控件 \(locator.summary)")
                } catch {
                    return (.failed, "断言失败: \(error.localizedDescription)")
                }
            }
            let result = await ocrEngine.findText(target, in: screenshot)
            return result.found ? (.success, nil) : (.failed, "断言失败: 未找到UI元素 '\(target)'")
        }
    }

    private func executeEventGroup(_ event: TestEvent, deviceUDID: String) async -> (EventStatus, String?) {
        guard let children = event.childEvents, !children.isEmpty else {
            return (.failed, "事件组为空")
        }

        switch event.executionMode {
        case .sequence:
            for child in children where child.isEnabled {
                guard !shouldStop else { return (.failed, "执行被中断") }
                let (status, err) = await executeEvent(child, deviceUDID: deviceUDID)
                if status == .failed { return (.failed, "事件组子事件失败: \(err ?? "")") }
            }
            return (.success, nil)

        case .parallel:
            var hasFailure = false
            var failMsg = ""
            await withTaskGroup(of: (EventStatus, String?).self) { group in
                for child in children where child.isEnabled {
                    group.addTask { await self.executeEvent(child, deviceUDID: deviceUDID) }
                }
                for await (status, err) in group {
                    if status == .failed {
                        hasFailure = true
                        failMsg = err ?? ""
                    }
                }
            }
            return hasFailure ? (.failed, "事件组并行执行部分失败: \(failMsg)") : (.success, nil)
        }
    }
}
