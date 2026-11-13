import SwiftUI

// MARK: - 主视图
struct MainView: View {
    @StateObject private var taskVM = TaskViewModel()
    @StateObject private var deviceVM = DeviceViewModel()
    @StateObject private var executionVM = ExecutionViewModel()
    @StateObject private var recordingVM = RecordingViewModel()

    @State private var selectedTab: SidebarTab = .tasks

    enum SidebarTab: String, CaseIterable, Identifiable {
        case tasks = "任务管理"
        case recordPreview = "录制/预览"
        case reports = "测试报告"
        case settings = "设置"

        var id: String { rawValue }

        var icon: String {
            switch self {
            case .tasks: return "list.bullet.clipboard"
            case .recordPreview: return "rectangle.on.rectangle"
            case .reports: return "chart.bar.doc.horizontal"
            case .settings: return "gear"
            }
        }
    }

    var body: some View {
        NavigationSplitView {
            // 侧边栏
            List(SidebarTab.allCases, selection: $selectedTab) { tab in
                Label(tab.rawValue, systemImage: tab.icon)
                    .tag(tab)
            }
            .listStyle(.sidebar)
            .navigationTitle("iOS 压测工具")
            .frame(minWidth: 180)

            // 底部状态
            VStack(spacing: 4) {
                Divider()
                HStack {
                    Circle()
                        .fill(deviceVM.connectedPhysicalDeviceCount > 0 ? .green : .red)
                        .frame(width: 8, height: 8)
                    Text("\(deviceVM.connectedPhysicalDeviceCount) 台真机")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    Spacer()
                    if executionVM.isExecuting {
                        ProgressView()
                            .scaleEffect(0.6)
                        Text("执行中")
                            .font(.caption)
                            .foregroundColor(.orange)
                    }
                }
                .padding(.horizontal, 12)
                .padding(.bottom, 8)
            }
        } detail: {
            // 主内容区
            Group {
                switch selectedTab {
                case .tasks:
                    TaskListView(
                        taskVM: taskVM,
                        deviceVM: deviceVM,
                        executionVM: executionVM,
                        recordingVM: recordingVM
                    )
                case .recordPreview:
                    HSplitView {
                        ScreenPreviewView(
                            deviceVM: deviceVM,
                            recordingVM: recordingVM,
                            executionVM: executionVM
                        )
                        .frame(minWidth: 420)

                        RecordingView(
                            recordingVM: recordingVM,
                            deviceVM: deviceVM,
                            taskVM: taskVM
                        )
                        .frame(minWidth: 420)
                    }
                case .reports:
                    ReportView()
                case .settings:
                    SettingsView()
                }
            }
            .frame(minWidth: 700, minHeight: 500)
        }
        .frame(minWidth: 1320, minHeight: 680)
        .onAppear {
            deviceVM.startPolling()
        }
        .onDisappear {
            deviceVM.stopPolling()
            taskVM.saveTasks()
        }
        .toolbar {
            ToolbarItemGroup(placement: .automatic) {
                if executionVM.isExecuting {
                    Text(executionVM.progressText)
                        .font(.caption)
                        .foregroundColor(.secondary)

                    ProgressView(value: executionVM.progressPercent, total: 100)
                        .frame(width: 120)

                    Button(action: { executionVM.stopExecution() }) {
                        Label("停止", systemImage: "stop.fill")
                            .foregroundColor(.red)
                    }
                }
            }
        }
    }
}
