import Foundation
import Combine

// MARK: - 录制视图模型
@MainActor
final class RecordingViewModel: ObservableObject {
    @Published var state: RecordingState = .idle
    @Published var recordedEvents: [RecordedRawEvent] = []
    @Published var elapsedTime: TimeInterval = 0
    @Published var statusMessage = ""
    /// 正在录制到哪个任务（展示用，例如 "登录流程 · 冒烟分组"）
    @Published private(set) var recordTargetName = ""
    private(set) var recordTargetTaskID: UUID?
    private var committedEventCount = 0
    private weak var targetTaskVM: TaskViewModel?

    private let recordingService = RecordingService.shared
    private let logger = Logger.shared
    private var cancellables = Set<AnyCancellable>()

    var eventCount: Int { recordedEvents.count }

    var formattedTime: String {
        recordingService.formattedElapsedTime
    }

    var canStart: Bool { state == .idle }
    var canPause: Bool { state == .recording }
    var canResume: Bool { state == .paused }
    var canStop: Bool { state == .recording || state == .paused }

    init() {
        recordingService.$state
            .receive(on: DispatchQueue.main)
            .assign(to: &$state)

        recordingService.$recordedEvents
            .receive(on: DispatchQueue.main)
            .assign(to: &$recordedEvents)

        recordingService.$elapsedTime
            .receive(on: DispatchQueue.main)
            .assign(to: &$elapsedTime)
    }

    // MARK: - 录制控制

    /// 开始录制：记录目标任务，之后每录到一条就追加进去。
    func startRecording(deviceUDID: String, deviceType: DeviceType,
                        targetTask: TestTask, taskVM: TaskViewModel) {
        recordTargetTaskID = targetTask.id
        recordTargetName = "\(targetTask.name) · \(targetTask.group)"
        targetTaskVM = taskVM
        committedEventCount = 0
        recordingService.startRecording(deviceUDID: deviceUDID, deviceType: deviceType)
        statusMessage = "录制中：点击/滑动会自动加入「\(recordTargetName)」"
    }

    func pauseRecording() {
        recordingService.pauseRecording()
        statusMessage = "录制已暂停"
    }

    func resumeRecording() {
        recordingService.resumeRecording()
        statusMessage = "录制已恢复"
    }

    /// 停止录制：先把最后一条补进去，再落盘。
    func stopRecordingAndCommit() {
        commitNewRecordedEvents()
        let events = recordingService.stopRecording()
        targetTaskVM?.saveTasks()
        statusMessage = "录制完成，共 \(events.count) 个事件"
        recordTargetTaskID = nil
        recordTargetName = ""
        committedEventCount = 0
    }

    /// 把"还没提交过"的录制事件转成 TestEvent 追加到目标任务。
    /// 用数量差做增量：convertToTestEvents() 每次返回整个列表，取尾部即可。
    func commitNewRecordedEvents() {
        guard let taskID = recordTargetTaskID, let taskVM = targetTaskVM else { return }
        let converted = recordingService.convertToTestEvents()
        guard converted.count > committedEventCount else { return }
        let newEvents = Array(converted[committedEventCount...])
        committedEventCount = converted.count
        taskVM.addEvents(to: taskID, events: newEvents)
        logger.info("录制追加 \(newEvents.count) 条到任务 \(recordTargetName)")
    }

    // MARK: - 事件录制 (由预览视图调用)

    func recordTap(x: Int, y: Int) {
        recordingService.recordTap(x: x, y: y)
    }

    func recordDoubleTap(x: Int, y: Int) {
        recordingService.recordDoubleTap(x: x, y: y)
    }

    func recordLongPress(x: Int, y: Int, duration: Double) {
        recordingService.recordLongPress(x: x, y: y, duration: duration)
    }

    func recordSwipe(startX: Int, startY: Int, endX: Int, endY: Int, duration: Double) {
        recordingService.recordSwipe(startX: startX, startY: startY, endX: endX, endY: endY, duration: duration)
    }

    func recordHardwareButton(_ type: EventType) {
        recordingService.recordHardwareButton(type)
    }

    // MARK: - 转换

    /// 把录制到的原始事件转成可执行的测试事件（含事件间隔 → delay）。
    /// 任务页的预览每录到一条就调它取增量，直接追加进当前任务。
    func convertToTestEvents() -> [TestEvent] {
        recordingService.convertToTestEvents()
    }
}
