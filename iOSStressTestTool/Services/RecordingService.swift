import Foundation
import Combine
import AppKit

// MARK: - 录制状态
enum RecordingState {
    case idle
    case recording
    case paused
}

// MARK: - 录制服务
/// 手机端操作自动录制服务
/// 支持两种录制模式:
/// 1. 屏幕交互录制: 通过监控截图变化和用户在预览窗口的操作来录制
/// 2. Accessibility Inspector 录制: 通过 macOS Accessibility 获取设备操作事件
@MainActor
final class RecordingService: ObservableObject {
    static let shared = RecordingService()

    @Published var state: RecordingState = .idle
    @Published var recordedEvents: [RecordedRawEvent] = []
    @Published var elapsedTime: TimeInterval = 0

    private let deviceService = DeviceService.shared
    private let screenshotService = ScreenshotService.shared
    private let logger = Logger.shared
    private let config = AppConfig.shared

    private var recordingStartTime: Date?
    private var lastEventTime: Date?
    private var elapsedTimer: Timer?
    private var monitorTask: Task<Void, Never>?

    // 录制设备信息
    private var recordingDeviceUDID: String?
    private var recordingDeviceType: DeviceType?

    private init() {}

    // MARK: - 录制控制

    /// 开始录制
    func startRecording(deviceUDID: String, deviceType: DeviceType) {
        guard state == .idle else {
            logger.warning("录制已在进行中")
            return
        }

        recordingDeviceUDID = deviceUDID
        recordingDeviceType = deviceType
        recordedEvents.removeAll()
        recordingStartTime = Date()
        lastEventTime = Date()
        state = .recording

        // 启动计时器
        elapsedTimer = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { [weak self] _ in
            guard let self, let start = self.recordingStartTime else { return }
            self.elapsedTime = Date().timeIntervalSince(start)
        }

        // 启动 simctl 事件监控 (模拟器)
        if deviceType == .simulator {
            startSimulatorEventMonitor(udid: deviceUDID)
        }

        logger.info("开始录制 - 设备: \(deviceUDID)")
    }

    /// 暂停录制
    func pauseRecording() {
        guard state == .recording else { return }
        state = .paused
        monitorTask?.cancel()
        logger.info("录制已暂停")
    }

    /// 恢复录制
    func resumeRecording() {
        guard state == .paused else { return }
        state = .recording
        lastEventTime = Date()

        if let udid = recordingDeviceUDID, recordingDeviceType == .simulator {
            startSimulatorEventMonitor(udid: udid)
        }

        logger.info("录制已恢复")
    }

    /// 停止录制
    func stopRecording() -> [RecordedRawEvent] {
        monitorTask?.cancel()
        monitorTask = nil
        elapsedTimer?.invalidate()
        elapsedTimer = nil

        state = .idle
        let events = recordedEvents

        logger.info("停止录制 - 共录制 \(events.count) 个事件")
        return events
    }

    // MARK: - 手动录制事件 (从预览窗口捕获)

    /// 录制点击事件 (从预览画布上的用户操作)
    func recordTap(x: Int, y: Int) {
        guard state == .recording else { return }

        let event = RecordedRawEvent(
            timestamp: Date(),
            type: .click,
            x: x, y: y,
            startX: nil, startY: nil,
            endX: nil, endY: nil,
            duration: nil,
            description: "点击 (\(x), \(y))"
        )
        appendEvent(event)
    }

    /// 录制双击事件
    func recordDoubleTap(x: Int, y: Int) {
        guard state == .recording else { return }

        let event = RecordedRawEvent(
            timestamp: Date(),
            type: .doubleClick,
            x: x, y: y,
            startX: nil, startY: nil,
            endX: nil, endY: nil,
            duration: nil,
            description: "双击 (\(x), \(y))"
        )
        appendEvent(event)
    }

    /// 录制长按事件
    func recordLongPress(x: Int, y: Int, duration: Double) {
        guard state == .recording else { return }

        let event = RecordedRawEvent(
            timestamp: Date(),
            type: .longPress,
            x: x, y: y,
            startX: nil, startY: nil,
            endX: nil, endY: nil,
            duration: duration,
            description: "长按 (\(x), \(y)) \(String(format: "%.1f", duration))s"
        )
        appendEvent(event)
    }

    /// 录制滑动事件
    func recordSwipe(startX: Int, startY: Int, endX: Int, endY: Int, duration: Double) {
        guard state == .recording else { return }

        let event = RecordedRawEvent(
            timestamp: Date(),
            type: .swipe,
            x: nil, y: nil,
            startX: startX, startY: startY,
            endX: endX, endY: endY,
            duration: duration,
            description: "滑动 (\(startX),\(startY)) -> (\(endX),\(endY))"
        )
        appendEvent(event)
    }

    /// 录制硬件按钮事件
    func recordHardwareButton(_ type: EventType) {
        guard state == .recording, type.isRecordable else { return }

        let event = RecordedRawEvent(
            timestamp: Date(),
            type: type,
            x: nil, y: nil,
            startX: nil, startY: nil,
            endX: nil, endY: nil,
            duration: nil,
            description: type.displayName
        )
        appendEvent(event)
    }

    // MARK: - 录制事件转换为测试事件

    /// 将录制的原始事件转换为可执行的测试事件列表
    func convertToTestEvents() -> [TestEvent] {
        var testEvents: [TestEvent] = []
        var previousTime: Date?

        for rawEvent in recordedEvents {
            var testEvent = TestEvent(type: rawEvent.type)

            // 计算与上一个事件的时间间隔作为延迟
            if let prevTime = previousTime, config.recordingAutoDelay {
                let interval = rawEvent.timestamp.timeIntervalSince(prevTime)
                testEvent.delay = min(max(interval, config.recordingMinDelay), config.recordingMaxDelay)
            } else {
                testEvent.delay = config.defaultEventDelay
            }

            testEvent.remark = rawEvent.description
            testEvent.recordedAt = rawEvent.timestamp

            switch rawEvent.type {
            case .click, .doubleClick, .longPress:
                testEvent.x = rawEvent.x
                testEvent.y = rawEvent.y
                if rawEvent.type == .longPress {
                    testEvent.pressDuration = rawEvent.duration ?? 1.0
                }

            case .swipe:
                testEvent.startX = rawEvent.startX
                testEvent.startY = rawEvent.startY
                testEvent.endX = rawEvent.endX
                testEvent.endY = rawEvent.endY
                testEvent.swipeDuration = rawEvent.duration ?? 0.5

            default:
                break
            }

            // 记录分辨率信息
            if let udid = recordingDeviceUDID,
               let device = deviceService.devices.first(where: { $0.udid == udid }) {
                testEvent.resolution = device.resolution
                testEvent.deviceUDID = udid
            }

            testEvents.append(testEvent)
            previousTime = rawEvent.timestamp
        }

        return testEvents
    }

    // MARK: - 模拟器事件监控

    /// 通过 simctl 事件流监控模拟器上的用户操作
    private func startSimulatorEventMonitor(udid: String) {
        monitorTask = Task { [weak self] in
            guard let self else { return }

            // 使用 simctl 的 io enumerate 或者通过截图差异检测
            // 注意: simctl 没有直接的事件流 API，这里使用截图差异检测
            var previousScreenshot: NSImage?

            while !Task.isCancelled && self.state == .recording {
                try? await Task.sleep(nanoseconds: 500_000_000) // 500ms

                guard let currentScreenshot = await self.screenshotService.captureScreenshot(
                    deviceUDID: udid, deviceType: .simulator
                ) else { continue }

                if let prev = previousScreenshot {
                    // 比较截图差异来检测是否发生了交互
                    let prevCG = prev.cgImage(forProposedRect: nil, context: nil, hints: nil)
                    let currCG = currentScreenshot.cgImage(forProposedRect: nil, context: nil, hints: nil)

                    if let p = prevCG, let c = currCG {
                        let similarity = ImageCompareUtils.shared.comparePixels(image1: p, image2: c)
                        if similarity < 0.95 {
                            self.logger.debug("检测到屏幕变化 (相似度: \(String(format: "%.2f", similarity)))")
                        }
                    }
                }

                previousScreenshot = currentScreenshot
            }
        }
    }

    // MARK: - 辅助方法

    private func appendEvent(_ event: RecordedRawEvent) {
        DispatchQueue.main.async {
            self.recordedEvents.append(event)
            self.lastEventTime = event.timestamp
        }
        logger.debug("录制事件: \(event.description)")

        // ⚠ 这里**不要**再"实时回放"一次。
        // 预览里的手势本来就会发给设备（ScreenPreviewView.previewTap/Swipe），
        // 录制时再执行一次等于每个点击都点两下 —— 之前的实现就是这样，只是录制页
        // 用得少没被发现。录制只负责"记下来并追加到任务"，执行交给预览自己做。
    }

    /// 格式化录制时长
    var formattedElapsedTime: String {
        let minutes = Int(elapsedTime) / 60
        let seconds = Int(elapsedTime) % 60
        let tenths = Int(elapsedTime * 10) % 10
        return String(format: "%02d:%02d.%d", minutes, seconds, tenths)
    }
}
