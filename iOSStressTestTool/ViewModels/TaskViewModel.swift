import Foundation
import Combine

// MARK: - 任务视图模型
/// 管理测试任务的创建、编辑、保存和加载
final class TaskViewModel: ObservableObject {
    @Published var tasks: [TestTask] = []
    @Published var selectedTask: TestTask?
    @Published var selectedEventIndex: Int?
    @Published var isModified = false
    @Published var searchText = ""

    private let logger = Logger.shared
    private var cancellables = Set<AnyCancellable>()

    // MARK: - 数据文件路径

    private var dataFileURL: URL {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let dir = appSupport.appendingPathComponent("iOSStressTestTool")
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.appendingPathComponent("tasks_data.json")
    }

    var filteredTasks: [TestTask] {
        if searchText.isEmpty { return tasks }
        return tasks.filter {
            $0.name.localizedCaseInsensitiveContains(searchText) ||
            $0.group.localizedCaseInsensitiveContains(searchText)
        }
    }

    var taskGroups: [String] {
        Array(Set(tasks.map { $0.group })).sorted()
    }

    init() {
        loadTasks()
    }

    // MARK: - 任务 CRUD

    func addTask(name: String, group: String = "默认分组", loopCount: Int = 1) {
        let task = TestTask(name: name, group: group, loopCount: loopCount)
        tasks.append(task)
        selectedTask = task
        isModified = true
        logger.info("创建任务: \(name)")
    }

    func duplicateTask(_ task: TestTask) {
        var copy = task
        copy.id = UUID()
        copy.name = "\(task.name) (副本)"
        copy.createdAt = Date()
        copy.updatedAt = Date()
        tasks.append(copy)
        isModified = true
    }

    func deleteTask(_ task: TestTask) {
        tasks.removeAll { $0.id == task.id }
        if selectedTask?.id == task.id {
            selectedTask = tasks.first
        }
        isModified = true
        logger.info("删除任务: \(task.name)")
    }

    func updateTask(_ task: TestTask) {
        guard let index = tasks.firstIndex(where: { $0.id == task.id }) else { return }
        var updated = task
        updated.updatedAt = Date()
        tasks[index] = updated
        if selectedTask?.id == task.id {
            selectedTask = updated
        }
        isModified = true
    }

    // MARK: - 事件管理

    func addEvent(to taskId: UUID, event: TestEvent) {
        guard let index = tasks.firstIndex(where: { $0.id == taskId }) else { return }
        tasks[index].events.append(event)
        tasks[index].updatedAt = Date()
        selectedTask = tasks[index]
        isModified = true
    }

    func addEvents(to taskId: UUID, events: [TestEvent]) {
        guard let index = tasks.firstIndex(where: { $0.id == taskId }) else { return }
        tasks[index].events.append(contentsOf: events)
        tasks[index].updatedAt = Date()
        selectedTask = tasks[index]
        isModified = true
    }

    func removeEvent(from taskId: UUID, at eventIndex: Int) {
        guard let index = tasks.firstIndex(where: { $0.id == taskId }),
              eventIndex < tasks[index].events.count else { return }
        tasks[index].events.remove(at: eventIndex)
        tasks[index].updatedAt = Date()
        selectedTask = tasks[index]
        isModified = true
    }

    func updateEvent(in taskId: UUID, at eventIndex: Int, event: TestEvent) {
        guard let index = tasks.firstIndex(where: { $0.id == taskId }),
              eventIndex < tasks[index].events.count else { return }
        tasks[index].events[eventIndex] = event
        tasks[index].updatedAt = Date()
        selectedTask = tasks[index]
        isModified = true
    }

    func moveEvent(in taskId: UUID, from source: IndexSet, to destination: Int) {
        guard let index = tasks.firstIndex(where: { $0.id == taskId }) else { return }
        tasks[index].events.move(fromOffsets: source, toOffset: destination)
        tasks[index].updatedAt = Date()
        selectedTask = tasks[index]
        isModified = true
    }

    // MARK: - 持久化

    func saveTasks() {
        let taskData = TaskDataFile(tasks: tasks, lastModified: Date())
        let encoder = JSONEncoder()
        encoder.outputFormatting = .prettyPrinted
        encoder.dateEncodingStrategy = .iso8601

        do {
            let data = try encoder.encode(taskData)
            try data.write(to: dataFileURL)
            isModified = false
            logger.info("任务数据已保存 (\(tasks.count) 个任务)")
        } catch {
            logger.error("保存任务数据失败: \(error)")
        }
    }

    func loadTasks() {
        guard FileManager.default.fileExists(atPath: dataFileURL.path) else {
            logger.info("无历史任务数据")
            return
        }

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601

        do {
            let data = try Data(contentsOf: dataFileURL)
            let taskData = try decoder.decode(TaskDataFile.self, from: data)
            tasks = taskData.tasks
            selectedTask = tasks.first
            logger.info("已加载 \(tasks.count) 个任务")
        } catch {
            logger.error("加载任务数据失败: \(error)")
        }
    }

    // MARK: - 导入/导出

    func exportTasks(to url: URL) {
        let taskData = TaskDataFile(tasks: tasks, lastModified: Date())
        let encoder = JSONEncoder()
        encoder.outputFormatting = .prettyPrinted
        encoder.dateEncodingStrategy = .iso8601

        do {
            let data = try encoder.encode(taskData)
            try data.write(to: url)
            logger.info("任务已导出到: \(url.path)")
        } catch {
            logger.error("导出任务失败: \(error)")
        }
    }

    func importTasks(from url: URL) {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601

        do {
            let data = try Data(contentsOf: url)
            let taskData = try decoder.decode(TaskDataFile.self, from: data)
            tasks.append(contentsOf: taskData.tasks)
            isModified = true
            logger.info("已导入 \(taskData.tasks.count) 个任务")
        } catch {
            logger.error("导入任务失败: \(error)")
        }
    }
}
