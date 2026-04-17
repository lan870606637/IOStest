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

        await MainActor.run {
            isExecuting = true
            shouldStop = false
        }

        let device = deviceService.devices.first { $0.udid == deviceUDID }
        let deviceName = device?.name ?? deviceUDID

        // 开始报告
        reportGenerator.startReport(taskName: task.name, deviceUDID: deviceUDID, deviceName: deviceName)

        logger.info("开始执行任务: \(task.name), 设备: \(deviceName), 循环次数: \(task.loopCount)")

        for loopIndex in 1...task.loopCount {
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

    /// 执行单个事件，返回 (状态, 错误消息)
    func executeEvent(_ event: TestEvent, deviceUDID: String) async -> (EventStatus, String?) {
        let eventReport = EventReportData(event: event)
        reportGenerator.startEvent(eventReport)

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

        reportGenerator.endEvent(status: result.0, errorMessage: result.1)
        return result
    }

    // MARK: - 具体事件执行

    private func executeClick(_ event: TestEvent, deviceUDID: String) async -> (EventStatus, String?) {
        guard let x = event.x, let y = event.y else {
            return (.failed, "点击坐标未设置")
        }
        let success = await deviceService.tap(udid: deviceUDID, x: x, y: y)
        return success ? (.success, nil) : (.failed, "点击执行失败")
    }

    private func executeDoubleClick(_ event: TestEvent, deviceUDID: String) async -> (EventStatus, String?) {
        guard let x = event.x, let y = event.y else {
            return (.failed, "双击坐标未设置")
        }
        // 快速执行两次点击
        let s1 = await deviceService.tap(udid: deviceUDID, x: x, y: y)
        try? await Task.sleep(nanoseconds: 100_000_000) // 100ms
        let s2 = await deviceService.tap(udid: deviceUDID, x: x, y: y)
        return (s1 && s2) ? (.success, nil) : (.failed, "双击执行失败")
    }

    private func executeLongPress(_ event: TestEvent, deviceUDID: String) async -> (EventStatus, String?) {
        guard let x = event.x, let y = event.y else {
            return (.failed, "长按坐标未设置")
        }
        let success = await deviceService.longPress(udid: deviceUDID, x: x, y: y, duration: event.pressDuration)
        return success ? (.success, nil) : (.failed, "长按执行失败")
    }

    private func executeSwipe(_ event: TestEvent, deviceUDID: String) async -> (EventStatus, String?) {
        guard let sx = event.startX, let sy = event.startY,
              let ex = event.endX, let ey = event.endY else {
            return (.failed, "滑动坐标未设置")
        }
        let success = await deviceService.swipe(
            udid: deviceUDID,
            startX: sx, startY: sy, endX: ex, endY: ey,
            duration: event.swipeDuration
        )
        return success ? (.success, nil) : (.failed, "滑动执行失败")
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
        guard let screenshot = await screenshotService.captureScreenshot(deviceUDID: deviceUDID, deviceType: device.deviceType) else {
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

        let success = await deviceService.tap(udid: deviceUDID, x: coords.x, y: coords.y)
        return success ? (.success, nil) : (.failed, "图像识别后点击失败")
    }

    private func executeOCRTextClick(_ event: TestEvent, deviceUDID: String) async -> (EventStatus, String?) {
        guard let targetText = event.targetText, !targetText.isEmpty else {
            return (.failed, "未指定目标文字")
        }

        guard let device = deviceService.devices.first(where: { $0.udid == deviceUDID }) else {
            return (.failed, "设备未找到")
        }

        guard let screenshot = await screenshotService.captureScreenshot(deviceUDID: deviceUDID, deviceType: device.deviceType) else {
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

        let success = await deviceService.tap(udid: deviceUDID, x: coords.x, y: coords.y)
        return success ? (.success, nil) : (.failed, "OCR 识别后点击失败")
    }

    private func executeScreenshot(_ event: TestEvent, deviceUDID: String) async -> (EventStatus, String?) {
        guard let device = deviceService.devices.first(where: { $0.udid == deviceUDID }) else {
            return (.failed, "设备未找到")
        }
        screenshotService.invalidateCache(for: deviceUDID)
        guard let screenshot = await screenshotService.captureScreenshot(deviceUDID: deviceUDID, deviceType: device.deviceType) else {
            return (.failed, "截图失败")
        }
        let name = event.remark.isEmpty ? "screenshot" : event.remark
        let _ = screenshotService.saveScreenshot(screenshot, name: name)
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
        guard let screenshot = await screenshotService.captureScreenshot(deviceUDID: deviceUDID, deviceType: device.deviceType),
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
        let success = await deviceService.terminateApp(udid: deviceUDID, bundleId: bundleId)
        return success ? (.success, nil) : (.failed, "终止应用失败")
    }

    private func executeLaunchApp(_ event: TestEvent, deviceUDID: String) async -> (EventStatus, String?) {
        guard let bundleId = event.bundleIdentifier, !bundleId.isEmpty else {
            return (.failed, "未指定应用 Bundle ID")
        }
        let success = await deviceService.launchApp(udid: deviceUDID, bundleId: bundleId)
        return success ? (.success, nil) : (.failed, "启动应用失败")
    }

    private func executeHardwareButton(_ type: EventType, deviceUDID: String) async -> (EventStatus, String?) {
        let success: Bool
        switch type {
        case .homeButton: success = await deviceService.pressHome(udid: deviceUDID)
        case .volumeUp: success = await deviceService.pressVolumeUp(udid: deviceUDID)
        case .volumeDown: success = await deviceService.pressVolumeDown(udid: deviceUDID)
        case .lockScreen: success = await deviceService.lockScreen(udid: deviceUDID)
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

        guard let screenshot = await screenshotService.captureScreenshot(deviceUDID: deviceUDID, deviceType: device.deviceType) else {
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
            // UI 元素断言通过 XCUITest 实现，此处做 OCR 降级
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
