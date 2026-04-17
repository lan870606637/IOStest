import Foundation

// MARK: - 事件报告数据
struct EventReportData: Identifiable, Codable {
    let id: UUID
    var eventType: EventType
    var eventName: String
    var remark: String
    var status: EventStatus = .pending
    var assertStatus: EventStatus?
    var startTime: Date?
    var endTime: Date?
    var duration: Double?
    var errorMessage: String?
    var screenshotPath: String?
    var assertScreenshotPath: String?
    var failScreenshotPath: String?
    var coordinates: String?

    init(event: TestEvent) {
        self.id = UUID()
        self.eventType = event.type
        self.eventName = event.type.displayName
        self.remark = event.remark
    }
}

// MARK: - 循环报告数据
struct LoopReportData: Identifiable, Codable {
    let id: UUID = UUID()
    var loopIndex: Int
    var events: [EventReportData] = []
    var startTime: Date?
    var endTime: Date?
    var status: EventStatus = .pending

    var totalEvents: Int { events.count }
    var successEvents: Int { events.filter { $0.status == .success }.count }
    var failedEvents: Int { events.filter { $0.status == .failed }.count }
    var successRate: Double {
        guard totalEvents > 0 else { return 0 }
        return Double(successEvents) / Double(totalEvents) * 100.0
    }
}

// MARK: - 测试报告
struct TestReport: Identifiable, Codable {
    let id: UUID = UUID()
    var taskName: String
    var deviceUDID: String
    var deviceName: String
    var loops: [LoopReportData] = []
    var startTime: Date?
    var endTime: Date?
    var status: EventStatus = .pending

    var totalLoops: Int { loops.count }
    var completedLoops: Int { loops.filter { $0.status == .success || $0.status == .failed }.count }
    var totalEvents: Int { loops.reduce(0) { $0 + $1.totalEvents } }
    var totalSuccessEvents: Int { loops.reduce(0) { $0 + $1.successEvents } }
    var totalFailedEvents: Int { loops.reduce(0) { $0 + $1.failedEvents } }
    var overallSuccessRate: Double {
        guard totalEvents > 0 else { return 0 }
        return Double(totalSuccessEvents) / Double(totalEvents) * 100.0
    }

    var duration: TimeInterval? {
        guard let start = startTime, let end = endTime else { return nil }
        return end.timeIntervalSince(start)
    }

    var formattedDuration: String {
        guard let dur = duration else { return "--" }
        let hours = Int(dur) / 3600
        let minutes = (Int(dur) % 3600) / 60
        let seconds = Int(dur) % 60
        return String(format: "%02d:%02d:%02d", hours, minutes, seconds)
    }

    var failedEvents: [EventReportData] {
        loops.flatMap { $0.events.filter { $0.status == .failed } }
    }
}
