import Foundation

// MARK: - 测试任务
struct TestTask: Identifiable, Codable {
    var id: UUID = UUID()
    var name: String
    var group: String = "默认分组"
    var loopCount: Int = 1
    var events: [TestEvent] = []
    var deviceUDID: String?
    var isEnabled: Bool = true
    var createdAt: Date = Date()
    var updatedAt: Date = Date()

    var enabledEvents: [TestEvent] {
        events.filter { $0.isEnabled }
    }

    var totalEventCount: Int {
        events.count
    }
}

// MARK: - 任务数据文件
struct TaskDataFile: Codable {
    var tasks: [TestTask]
    var version: String = "1.0"
    var lastModified: Date = Date()
}
