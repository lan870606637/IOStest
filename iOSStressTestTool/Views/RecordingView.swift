import SwiftUI

// MARK: - 录制视图
struct RecordingView: View {
    @ObservedObject var recordingVM: RecordingViewModel
    @ObservedObject var deviceVM: DeviceViewModel
    @ObservedObject var taskVM: TaskViewModel

    @State private var taskName = ""
    @State private var showSaveSheet = false

    var body: some View {
        VStack(spacing: 0) {
            // 标题栏
            HStack {
                Text("事件录制")
                    .font(.title2.bold())
                Spacer()

                if recordingVM.state != .idle {
                    HStack(spacing: 4) {
                        Circle()
                            .fill(recordingVM.state == .recording ? .red : .orange)
                            .frame(width: 10, height: 10)
                        Text(recordingVM.formattedTime)
                            .font(.system(.title3, design: .monospaced))
                    }
                }
            }
            .padding()
            .background(Color(nsColor: .controlBackgroundColor))

            Divider()

            HSplitView {
                // 左侧: 控制面板
                VStack(alignment: .leading, spacing: 16) {
                    // 设备选择
                    GroupBox("录制设备") {
                        VStack(alignment: .leading, spacing: 8) {
                            if let device = deviceVM.selectedDevice {
                                HStack {
                                    Image(systemName: "iphone")
                                    Text(device.displayTitle)
                                }
                            } else {
                                Text("请先在任务管理顶部选择已连接真机")
                                    .foregroundColor(.secondary)
                            }
                        }
                        .padding(4)
                    }

                    // 录制控制
                    GroupBox("录制控制") {
                        VStack(spacing: 12) {
                            HStack(spacing: 12) {
                                // 开始录制
                                Button(action: { startRecording() }) {
                                    Label("开始录制", systemImage: "record.circle")
                                        .frame(maxWidth: .infinity)
                                        .padding(.vertical, 8)
                                }
                                .buttonStyle(.borderedProminent)
                                .tint(.red)
                                .disabled(!recordingVM.canStart || deviceVM.selectedDevice == nil)

                                // 暂停/恢复
                                if recordingVM.state == .recording {
                                    Button(action: { recordingVM.pauseRecording() }) {
                                        Label("暂停", systemImage: "pause.fill")
                                            .frame(maxWidth: .infinity)
                                            .padding(.vertical, 8)
                                    }
                                } else if recordingVM.state == .paused {
                                    Button(action: { recordingVM.resumeRecording() }) {
                                        Label("恢复", systemImage: "play.fill")
                                            .frame(maxWidth: .infinity)
                                            .padding(.vertical, 8)
                                    }
                                    .buttonStyle(.borderedProminent)
                                    .tint(.orange)
                                }
                            }

                            if recordingVM.canStop {
                                Button(action: { stopAndSave() }) {
                                    Label("停止录制", systemImage: "stop.fill")
                                        .frame(maxWidth: .infinity)
                                        .padding(.vertical, 8)
                                }
                                .tint(.gray)
                            }
                        }
                        .padding(4)
                    }

                    // 使用说明
                    GroupBox("操作说明") {
                        VStack(alignment: .leading, spacing: 6) {
                            instructionRow("1.", "选择要录制的设备")
                            instructionRow("2.", "点击「开始录制」")
                            instructionRow("3.", "在左侧「屏幕预览」画面上操作")
                            instructionRow("4.", "在预览画面上操作:")
                            instructionRow("  -", "单击 = 点击事件")
                            instructionRow("  -", "拖拽 = 滑动事件")
                            instructionRow("  -", "长按 >0.5s = 长按事件")
                            instructionRow("  -", "使用右侧按钮 = 硬件按钮事件")
                            instructionRow("5.", "停止录制，保存为任务")
                        }
                        .font(.caption)
                        .padding(4)
                    }

                    // 状态消息
                    if !recordingVM.statusMessage.isEmpty {
                        Text(recordingVM.statusMessage)
                            .font(.caption)
                            .foregroundColor(.secondary)
                            .padding(.horizontal)
                    }

                    Spacer()
                }
                .padding()
                .frame(minWidth: 280, maxWidth: 320)

                // 右侧: 录制的事件列表
                VStack(spacing: 0) {
                    HStack {
                        Text("已录制事件 (\(recordingVM.eventCount))")
                            .font(.headline)
                        Spacer()
                        if !recordingVM.recordedEvents.isEmpty {
                            Button("清除") { recordingVM.clearRecording() }
                                .disabled(recordingVM.state == .recording)
                        }
                    }
                    .padding()

                    Divider()

                    if recordingVM.recordedEvents.isEmpty {
                        VStack(spacing: 12) {
                            Image(systemName: "waveform.path.ecg")
                                .font(.system(size: 48))
                                .foregroundColor(.secondary)
                            Text("尚无录制事件")
                                .foregroundColor(.secondary)
                            Text("开始录制后，在屏幕预览中的操作将被记录")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                    } else {
                        List {
                            ForEach(Array(recordingVM.recordedEvents.enumerated()), id: \.element.id) { index, event in
                                RecordedEventRow(event: event, index: index)
                                    .contextMenu {
                                        Button("删除", role: .destructive) {
                                            recordingVM.deleteEvent(at: index)
                                        }
                                    }
                            }
                        }
                        .listStyle(.inset)

                        Divider()

                        // 保存操作栏
                        HStack {
                            Spacer()
                            Button("保存为任务...") { showSaveSheet = true }
                                .buttonStyle(.borderedProminent)
                                .disabled(recordingVM.recordedEvents.isEmpty || recordingVM.state == .recording)
                        }
                        .padding(8)
                    }
                }
            }
        }
        .sheet(isPresented: $showSaveSheet) {
            saveTaskSheet
        }
    }

    // MARK: - 保存为任务

    private var saveTaskSheet: some View {
        VStack(spacing: 16) {
            Text("保存录制为任务").font(.headline)

            TextField("任务名称", text: $taskName)
                .textFieldStyle(.roundedBorder)
                .frame(width: 300)

            Text("共 \(recordingVM.eventCount) 个事件将被保存")
                .font(.caption)
                .foregroundColor(.secondary)

            HStack {
                Button("取消") { showSaveSheet = false }
                Button("保存") {
                    guard !taskName.isEmpty else { return }
                    recordingVM.createTaskFromRecording(name: taskName, taskViewModel: taskVM)
                    showSaveSheet = false
                    taskName = ""
                }
                .buttonStyle(.borderedProminent)
                .disabled(taskName.isEmpty)
            }
        }
        .padding(30)
    }

    // MARK: - 辅助视图

    private func instructionRow(_ num: String, _ text: String) -> some View {
        HStack(alignment: .top, spacing: 4) {
            Text(num).foregroundColor(.secondary).frame(width: 20, alignment: .trailing)
            Text(text)
        }
    }

    private func startRecording() {
        guard let device = deviceVM.selectedDevice else { return }
        recordingVM.startRecording(deviceUDID: device.udid, deviceType: device.deviceType)
    }

    private func stopAndSave() {
        _ = recordingVM.stopRecording()
        if !recordingVM.recordedEvents.isEmpty {
            showSaveSheet = true
            taskName = "录制_\(DateFormatter.fileNameFormatter.string(from: Date()))"
        }
    }
}

// MARK: - 录制事件行

struct RecordedEventRow: View {
    let event: RecordedRawEvent
    let index: Int

    var body: some View {
        HStack(spacing: 10) {
            Text("\(index + 1)")
                .font(.caption.monospacedDigit())
                .foregroundColor(.secondary)
                .frame(width: 24)

            Image(systemName: iconName)
                .foregroundColor(iconColor)
                .frame(width: 20)

            VStack(alignment: .leading, spacing: 2) {
                Text(event.type.displayName)
                    .fontWeight(.medium)
                Text(event.description)
                    .font(.caption)
                    .foregroundColor(.secondary)
            }

            Spacer()

            Text(timeString)
                .font(.caption.monospacedDigit())
                .foregroundColor(.secondary)
        }
    }

    private var iconName: String {
        switch event.type {
        case .click: return "hand.tap"
        case .doubleClick: return "hand.tap"
        case .longPress: return "hand.point.down"
        case .swipe: return "hand.draw"
        case .homeButton: return "house"
        case .volumeUp: return "speaker.plus"
        case .volumeDown: return "speaker.minus"
        case .lockScreen: return "lock"
        case .shake: return "iphone.radiowaves.left.and.right"
        default: return "circle"
        }
    }

    private var iconColor: Color {
        switch event.type {
        case .click, .doubleClick: return .blue
        case .longPress: return .orange
        case .swipe: return .green
        default: return .purple
        }
    }

    private var timeString: String {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm:ss"
        return formatter.string(from: event.timestamp)
    }
}
