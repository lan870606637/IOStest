import SwiftUI

// MARK: - 任务列表视图
struct TaskListView: View {
    @ObservedObject var taskVM: TaskViewModel
    @ObservedObject var deviceVM: DeviceViewModel
    @ObservedObject var executionVM: ExecutionViewModel

    @State private var showAddTask = false
    @State private var newTaskName = ""
    @State private var newTaskGroup = "默认分组"
    @State private var newTaskLoopCount = 1
    @State private var showEventEditor = false
    @State private var editingEventIndex: Int?
    @State private var showEditTask = false
    @State private var editingTaskID: UUID?
    @State private var editTaskName = ""
    @State private var editTaskGroup = ""
    @State private var editTaskLoopCount = 1

    var body: some View {
        VStack(spacing: 0) {
            physicalDeviceBar
            Divider()
            HSplitView {
            // 左侧: 任务列表
            VStack(spacing: 0) {
                // 搜索和操作栏
                HStack {
                    Image(systemName: "magnifyingglass")
                        .foregroundColor(.secondary)
                    TextField("搜索任务...", text: $taskVM.searchText)
                        .textFieldStyle(.plain)
                    Spacer()
                    Button(action: { showAddTask.toggle() }) {
                        Image(systemName: "plus")
                    }
                    .popover(isPresented: $showAddTask) {
                        addTaskPopover
                    }
                }
                .padding(10)
                .background(Color(nsColor: .controlBackgroundColor))

                Divider()

                // 任务列表
                List(taskVM.filteredTasks, selection: Binding(
                    get: { taskVM.selectedTask?.id },
                    set: { id in taskVM.selectedTask = taskVM.tasks.first { $0.id == id } }
                )) { task in
                    TaskRow(task: task)
                        .contextMenu {
                            Button("编辑任务") { beginEditTask(task) }
                            Button("复制任务") { taskVM.duplicateTask(task) }
                            Divider()
                            Button("删除任务", role: .destructive) { taskVM.deleteTask(task) }
                        }
                }
                .listStyle(.inset)

                Divider()

                // 底部操作栏
                HStack {
                    Text("\(taskVM.tasks.count) 个任务")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    Spacer()
                    Button("保存") { taskVM.saveTasks() }
                        .disabled(!taskVM.isModified)
                }
                .padding(8)
            }
            .frame(minWidth: 250, maxWidth: 350)

            // 右侧: 任务详情与事件列表
            if let task = taskVM.selectedTask {
                taskDetailView(task)
            } else {
                VStack {
                    Image(systemName: "doc.text.magnifyingglass")
                        .font(.system(size: 48))
                        .foregroundColor(.secondary)
                    Text("选择一个任务查看详情")
                        .foregroundColor(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        }
        .onAppear { selectConnectedPhysicalIfNeeded() }
        .onChange(of: deviceVM.devices) { _, _ in selectConnectedPhysicalIfNeeded() }
    }

    // MARK: - 真机选择栏

    private var connectedPhysicalDevices: [DeviceInfo] {
        deviceVM.connectedPhysicalDevices
    }

    private var canExecute: Bool {
        guard let device = deviceVM.selectedDevice else { return false }
        return device.deviceType == .physical && device.status == .connected
    }

    private var physicalDeviceBar: some View {
        HStack(spacing: 12) {
            Label("真机", systemImage: "iphone")
                .font(.headline)

            if connectedPhysicalDevices.isEmpty {
                Text("未连接真机，请用 USB 连接 iPhone，信任电脑并开启开发者模式")
                    .font(.caption)
                    .foregroundColor(.orange)
            } else if connectedPhysicalDevices.count == 1,
                      let device = connectedPhysicalDevices.first {
                Circle()
                    .fill(.green)
                    .frame(width: 8, height: 8)
                Text("\(device.name) · \(device.osVersion)")
            } else {
                Picker("", selection: Binding(
                    get: { selectedPhysicalUDID },
                    set: { udid in
                        if let device = connectedPhysicalDevices.first(where: { $0.udid == udid }) {
                            deviceVM.selectDevice(device)
                        }
                    }
                )) {
                    ForEach(connectedPhysicalDevices) { device in
                        Text("\(device.name) · \(device.osVersion)").tag(device.udid)
                    }
                }
                .labelsHidden()
                .frame(width: 260)

                Circle()
                    .fill(.green)
                    .frame(width: 8, height: 8)
                Text("已连接 \(connectedPhysicalDevices.count) 台")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }

            Button {
                Task { await deviceVM.refreshDevices() }
            } label: {
                if deviceVM.isRefreshing {
                    ProgressView()
                        .scaleEffect(0.6)
                } else {
                    Image(systemName: "arrow.clockwise")
                }
            }
            .help("刷新真机列表")
            .disabled(deviceVM.isRefreshing)

            Spacer()
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(Color(nsColor: .controlBackgroundColor))
    }

    private var selectedPhysicalUDID: String {
        if let selected = deviceVM.selectedDevice,
           selected.deviceType == .physical,
           connectedPhysicalDevices.contains(where: { $0.udid == selected.udid }) {
            return selected.udid
        }
        return connectedPhysicalDevices.first?.udid ?? ""
    }

    private func selectConnectedPhysicalIfNeeded() {
        let devices = connectedPhysicalDevices
        guard !devices.isEmpty else {
            if let selected = deviceVM.selectedDevice,
               selected.deviceType != .physical || selected.status != .connected {
                deviceVM.clearSelection()
            }
            return
        }

        if let selected = deviceVM.selectedDevice,
           selected.deviceType == .physical,
           selected.status == .connected,
           devices.contains(where: { $0.udid == selected.udid }) {
            return
        }

        deviceVM.selectDevice(devices[0])
    }

    // MARK: - 任务详情

    @ViewBuilder
    private func taskDetailView(_ task: TestTask) -> some View {
        VStack(spacing: 0) {
            // 任务信息头
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text(task.name)
                        .font(.title2.bold())
                    HStack(spacing: 12) {
                        Label(task.group, systemImage: "folder")
                        Label("循环 \(task.loopCount) 次", systemImage: "repeat")
                        Label("\(task.enabledEvents.count) 个事件", systemImage: "list.number")
                    }
                    .font(.caption)
                    .foregroundColor(.secondary)
                }
                Spacer()

                Button(action: { beginEditTask(task) }) {
                    Label("编辑", systemImage: "pencil")
                }

                // 执行按钮
                Button(action: { startExecution(task) }) {
                    Label("执行", systemImage: "play.fill")
                        .padding(.horizontal, 12)
                        .padding(.vertical, 6)
                }
                .buttonStyle(.borderedProminent)
                .tint(.green)
                .disabled(executionVM.isExecuting || !canExecute)
            }
            .padding()
            .background(Color(nsColor: .controlBackgroundColor))

            Divider()

            // 事件列表
            List {
                ForEach(Array(task.events.enumerated()), id: \.element.id) { index, event in
                    EventRow(event: event, index: index)
                        .contextMenu {
                            Button("编辑") {
                                editingEventIndex = index
                                showEventEditor = true
                            }
                            Button("复制") {
                                var copy = event
                                copy.id = UUID()
                                taskVM.addEvent(to: task.id, event: copy)
                            }
                            Button(event.isEnabled ? "禁用" : "启用") {
                                var updated = event
                                updated.isEnabled.toggle()
                                taskVM.updateEvent(in: task.id, at: index, event: updated)
                            }
                            Divider()
                            Button("删除", role: .destructive) {
                                taskVM.removeEvent(from: task.id, at: index)
                            }
                        }
                }
                .onMove { source, dest in
                    taskVM.moveEvent(in: task.id, from: source, to: dest)
                }
            }

            Divider()

            // 事件操作栏
            HStack {
                Button(action: { addNewEvent(to: task) }) {
                    Label("添加事件", systemImage: "plus")
                }

                Menu("快捷添加") {
                    ForEach(EventType.allCases) { type in
                        Button(type.displayName) {
                            let event = TestEvent(type: type)
                            taskVM.addEvent(to: task.id, event: event)
                        }
                    }
                }

                Spacer()

                if executionVM.isExecuting {
                    Button(action: { executionVM.stopExecution() }) {
                        Label("停止执行", systemImage: "stop.fill")
                            .foregroundColor(.red)
                    }
                }
            }
            .padding(8)

            // 执行日志 (折叠面板)
            if !executionVM.executionLog.isEmpty {
                Divider()
                DisclosureGroup("执行日志 (\(executionVM.executionLog.count) 行)") {
                    ScrollView {
                        LazyVStack(alignment: .leading, spacing: 1) {
                            ForEach(executionVM.executionLog.suffix(200), id: \.self) { line in
                                Text(line)
                                    .font(.system(.caption, design: .monospaced))
                                    .foregroundColor(line.contains("FAIL") ? .red : .primary)
                            }
                        }
                        .padding(6)
                    }
                    .frame(maxHeight: 200)
                    .background(Color(nsColor: .textBackgroundColor))
                }
                .padding(.horizontal, 8)
                .padding(.bottom, 4)
            }
        }
        .sheet(isPresented: $showEventEditor) {
            if let task = taskVM.selectedTask {
                EventEditorView(
                    event: currentEditingEvent(for: task),
                    onSave: { updated in
                        if let index = editingEventIndex, index < task.events.count {
                            taskVM.updateEvent(in: task.id, at: index, event: updated)
                        } else {
                            taskVM.addEvent(to: task.id, event: updated)
                        }
                        showEventEditor = false
                    },
                    onCancel: { showEventEditor = false }
                )
            }
        }
        .sheet(isPresented: $showEditTask) {
            editTaskSheet
        }
    }

    // MARK: - 添加任务弹窗

    private var addTaskPopover: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("新建任务").font(.headline)
            TextField("任务名称", text: $newTaskName)
                .textFieldStyle(.roundedBorder)
            TextField("分组", text: $newTaskGroup)
                .textFieldStyle(.roundedBorder)
            HStack {
                Text("循环次数")
                    .frame(width: 70, alignment: .trailing)
                TextField("", value: $newTaskLoopCount, format: .number)
                    .textFieldStyle(.roundedBorder)
                    .frame(width: 90)
                Text("次")
            }
            HStack {
                Spacer()
                Button("取消") { showAddTask = false }
                Button("创建") {
                    guard !newTaskName.isEmpty else { return }
                    taskVM.addTask(name: newTaskName, group: newTaskGroup, loopCount: max(1, newTaskLoopCount))
                    newTaskName = ""
                    showAddTask = false
                }
                .buttonStyle(.borderedProminent)
            }
        }
        .padding()
        .frame(width: 300)
    }

    // MARK: - 辅助方法

    private func currentEditingEvent(for task: TestTask) -> TestEvent {
        if let index = editingEventIndex, index < task.events.count {
            return task.events[index]
        }
        return TestEvent(type: .click)
    }

    private var editTaskSheet: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("编辑任务").font(.headline)
            TextField("任务名称", text: $editTaskName)
                .textFieldStyle(.roundedBorder)
            TextField("分组", text: $editTaskGroup)
                .textFieldStyle(.roundedBorder)
            HStack {
                Text("循环次数")
                    .frame(width: 70, alignment: .trailing)
                TextField("", value: $editTaskLoopCount, format: .number)
                    .textFieldStyle(.roundedBorder)
                    .frame(width: 90)
                Text("次")
            }
            HStack {
                Spacer()
                Button("取消") { showEditTask = false }
                Button("保存") { saveEditedTask() }
                    .buttonStyle(.borderedProminent)
            }
        }
        .padding()
        .frame(width: 340)
    }

    private func beginEditTask(_ task: TestTask) {
        editingTaskID = task.id
        editTaskName = task.name
        editTaskGroup = task.group
        editTaskLoopCount = task.loopCount
        showEditTask = true
    }

    private func saveEditedTask() {
        guard let id = editingTaskID,
              let task = taskVM.tasks.first(where: { $0.id == id }) else {
            showEditTask = false
            return
        }

        var updated = task
        let name = editTaskName.trimmingCharacters(in: .whitespacesAndNewlines)
        let group = editTaskGroup.trimmingCharacters(in: .whitespacesAndNewlines)
        updated.name = name.isEmpty ? task.name : name
        updated.group = group.isEmpty ? "默认分组" : group
        updated.loopCount = max(1, editTaskLoopCount)

        taskVM.updateTask(updated)
        taskVM.saveTasks()
        showEditTask = false
    }

    private func startExecution(_ task: TestTask) {
        guard let device = deviceVM.selectedDevice,
              device.deviceType == .physical,
              device.status == .connected else { return }
        executionVM.executeTask(task, deviceUDID: device.udid)
    }

    private func addNewEvent(to task: TestTask) {
        editingEventIndex = nil
        showEventEditor = true
    }
}

// MARK: - 任务行

struct TaskRow: View {
    let task: TestTask

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(task.name)
                    .fontWeight(.medium)
                Spacer()
                Text("\(task.events.count)")
                    .font(.caption)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(Color.accentColor.opacity(0.2))
                    .clipShape(Capsule())
            }
            HStack(spacing: 8) {
                Text(task.group)
                Text("x\(task.loopCount)")
            }
            .font(.caption)
            .foregroundColor(.secondary)
        }
        .padding(.vertical, 2)
    }
}

// MARK: - 事件行

struct EventRow: View {
    let event: TestEvent
    let index: Int

    var body: some View {
        HStack(spacing: 10) {
            Text("\(index + 1)")
                .font(.caption.monospacedDigit())
                .foregroundColor(.secondary)
                .frame(width: 24)

            Circle()
                .fill(event.isEnabled ? eventColor : .gray)
                .frame(width: 8, height: 8)

            VStack(alignment: .leading, spacing: 2) {
                Text(event.type.displayName)
                    .fontWeight(.medium)
                    .opacity(event.isEnabled ? 1 : 0.5)
                if !event.remark.isEmpty {
                    Text(event.remark)
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }

            Spacer()

            // 坐标/参数预览
            Text(eventDetail)
                .font(.caption)
                .foregroundColor(.secondary)

            Text(String(format: "%.1fs", event.delay))
                .font(.caption.monospacedDigit())
                .foregroundColor(.secondary)
        }
    }

    private var eventColor: Color {
        switch event.type {
        case .click, .doubleClick, .longPress: return .blue
        case .swipe: return .orange
        case .imageRecognitionClick: return .purple
        case .ocrTextClick: return .cyan
        case .popupButton: return .pink
        case .screenshot, .compareScreenshot: return .green
        case .assertion: return .yellow
        case .eventGroup: return .indigo
        default: return .gray
        }
    }

    private var eventDetail: String {
        switch event.type {
        case .click, .doubleClick, .longPress:
            if let x = event.x, let y = event.y { return "(\(x), \(y))" }
        case .swipe:
            if let sx = event.startX, let sy = event.startY,
               let ex = event.endX, let ey = event.endY {
                return "(\(sx),\(sy))->(\(ex),\(ey))"
            }
        case .imageRecognitionClick:
            return event.templateName ?? ""
        case .ocrTextClick:
            return event.targetText ?? ""
        case .popupButton:
            return event.popupButtonText ?? ""
        case .killApp, .launchApp:
            return event.bundleIdentifier ?? ""
        default: break
        }
        return ""
    }
}
