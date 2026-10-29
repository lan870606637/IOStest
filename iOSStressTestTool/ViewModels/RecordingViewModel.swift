import Foundation
import Combine

// MARK: - 录制视图模型
@MainActor
final class RecordingViewModel: ObservableObject {
    @Published var state: RecordingState = .idle
    @Published var recordedEvents: [RecordedRawEvent] = []
    @Published var elapsedTime: TimeInterval = 0
    @Published var statusMessage = ""
    @Published var isConvertingToTask = false

    private let recordingService = RecordingService.shared
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

    func startRecording(deviceUDID: String, deviceType: DeviceType) {
        recordingService.startRecording(deviceUDID: deviceUDID, deviceType: deviceType)
        statusMessage = "录制中... 在预览画面上操作以录制事件"
    }

    func pauseRecording() {
        recordingService.pauseRecording()
        statusMessage = "录制已暂停"
    }

    func resumeRecording() {
        recordingService.resumeRecording()
        statusMessage = "录制已恢复"
    }

    func stopRecording() -> [RecordedRawEvent] {
        let events = recordingService.stopRecording()
        statusMessage = "录制完成，共 \(events.count) 个事件"
        return events
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

    // MARK: - 转换为任务

    func convertToTestEvents() -> [TestEvent] {
        return recordingService.convertToTestEvents()
    }

    func createTaskFromRecording(name: String, taskViewModel: TaskViewModel) {
        isConvertingToTask = true
        let events = convertToTestEvents()
        taskViewModel.addTask(name: name, loopCount: 1)

        if let task = taskViewModel.tasks.last {
            taskViewModel.addEvents(to: task.id, events: events)
            statusMessage = "已创建任务: \(name) (\(events.count) 个事件)"
        }
        isConvertingToTask = false
    }

    // MARK: - 辅助

    func clearRecording() {
        recordedEvents.removeAll()
        statusMessage = ""
    }

    func deleteEvent(at index: Int) {
        guard index < recordedEvents.count else { return }
        recordedEvents.remove(at: index)
    }
}
