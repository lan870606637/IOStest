import Foundation
import Combine

// MARK: - 执行视图模型
final class ExecutionViewModel: ObservableObject {
    @Published var isExecuting = false
    @Published var progress: ExecutionProgress?
    @Published var executionLog: [String] = []
    @Published var currentLoopIndex = 0
    @Published var totalLoops = 0
    @Published var currentEventIndex = 0
    @Published var totalEvents = 0

    private let executor = EventExecutor.shared
    private let logger = Logger.shared
    private var cancellables = Set<AnyCancellable>()

    var progressPercent: Double {
        guard totalLoops > 0, totalEvents > 0 else { return 0 }
        let loopProgress = Double(currentLoopIndex - 1) / Double(totalLoops)
        let eventProgress = Double(currentEventIndex) / Double(totalEvents) / Double(totalLoops)
        return min((loopProgress + eventProgress) * 100, 100)
    }

    var progressText: String {
        guard isExecuting else { return "就绪" }
        return "循环 \(currentLoopIndex)/\(totalLoops) - 事件 \(currentEventIndex)/\(totalEvents)"
    }

    init() {
        executor.$isExecuting
            .receive(on: DispatchQueue.main)
            .assign(to: &$isExecuting)

        executor.onProgress = { [weak self] progress in
            DispatchQueue.main.async {
                self?.progress = progress
                self?.currentLoopIndex = progress.currentLoop
                self?.totalLoops = progress.totalLoops
                self?.currentEventIndex = progress.currentEventIndex
                self?.totalEvents = progress.totalEvents
                self?.appendLog(progress.message)
            }
        }

        executor.onEventComplete = { [weak self] event, status, error in
            DispatchQueue.main.async {
                let statusIcon = status == .success ? "OK" : "FAIL"
                var msg = "[\(statusIcon)] \(event.type.displayName)"
                if !event.remark.isEmpty { msg += " - \(event.remark)" }
                if let err = error { msg += " | \(err)" }
                self?.appendLog(msg)
            }
        }
    }

    // MARK: - 执行控制

    func executeTask(_ task: TestTask, deviceUDID: String) {
        guard !isExecuting else {
            logger.warning("已有任务执行中")
            return
        }

        executionLog.removeAll()
        appendLog("开始执行任务: \(task.name)")
        appendLog("设备: \(deviceUDID)")
        appendLog("循环次数: \(task.loopCount)")
        appendLog("事件数: \(task.enabledEvents.count)")
        appendLog("---")

        Task {
            await executor.executeTask(task, deviceUDID: deviceUDID)
            await MainActor.run {
                self.appendLog("---")
                self.appendLog("任务执行完成")
            }
        }
    }

    func stopExecution() {
        executor.stop()
        appendLog("正在停止执行...")
    }

    /// 执行单个事件 (用于调试)
    func executeSingleEvent(_ event: TestEvent, deviceUDID: String) {
        Task {
            let (status, error) = await executor.executeEvent(event, deviceUDID: deviceUDID)
            await MainActor.run {
                let msg = status == .success
                    ? "事件执行成功: \(event.type.displayName)"
                    : "事件执行失败: \(error ?? "")"
                self.appendLog(msg)
            }
        }
    }

    // MARK: - 日志

    private func appendLog(_ message: String) {
        let timestamp = DateFormatter.logTimestampFormatter.string(from: Date())
        executionLog.append("[\(timestamp)] \(message)")

        // 限制日志行数
        if executionLog.count > 5000 {
            executionLog.removeFirst(1000)
        }
    }

    func clearLog() {
        executionLog.removeAll()
    }

    func exportLog() -> String {
        executionLog.joined(separator: "\n")
    }
}

extension DateFormatter {
    static let logTimestampFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "HH:mm:ss"
        return f
    }()
}
