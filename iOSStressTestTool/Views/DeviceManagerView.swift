import SwiftUI

// MARK: - 设备管理视图
struct DeviceManagerView: View {
    @ObservedObject var deviceVM: DeviceViewModel

    @State private var bundleIdInput = ""
    @State private var appPathInput = ""

    var body: some View {
        VStack(spacing: 0) {
            // 顶部工具栏
            HStack {
                Text("设备管理")
                    .font(.title2.bold())
                Spacer()

                Picker("筛选", selection: $deviceVM.filterType) {
                    ForEach(DeviceViewModel.DeviceFilterType.allCases, id: \.self) { type in
                        Text(type.rawValue).tag(type)
                    }
                }
                .pickerStyle(.segmented)
                .frame(width: 300)

                Button(action: {
                    Task { await deviceVM.refreshDevices() }
                }) {
                    Label("刷新", systemImage: "arrow.clockwise")
                }
                .disabled(deviceVM.isRefreshing)
            }
            .padding()
            .background(Color(nsColor: .controlBackgroundColor))

            Divider()

            HSplitView {
                // 设备列表
                List(deviceVM.filteredDevices, selection: Binding(
                    get: { deviceVM.selectedDevice?.udid },
                    set: { udid in
                        if let device = deviceVM.devices.first(where: { $0.udid == udid }) {
                            deviceVM.selectDevice(device)
                        }
                    }
                )) { device in
                    DeviceRow(device: device)
                        .tag(device.udid)
                }
                .listStyle(.inset)
                .frame(minWidth: 300)

                // 设备详情
                if let device = deviceVM.selectedDevice {
                    deviceDetailView(device)
                } else {
                    VStack {
                        Image(systemName: "iphone.slash")
                            .font(.system(size: 48))
                            .foregroundColor(.secondary)
                        Text("选择一台设备")
                            .foregroundColor(.secondary)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            }

            // 状态栏
            if !deviceVM.statusMessage.isEmpty {
                Divider()
                HStack {
                    if deviceVM.isRefreshing {
                        ProgressView()
                            .scaleEffect(0.7)
                    }
                    Text(deviceVM.statusMessage)
                        .font(.caption)
                        .foregroundColor(.secondary)
                    Spacer()
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .background(Color(nsColor: .controlBackgroundColor))
            }
        }
    }

    // MARK: - 设备详情

    @ViewBuilder
    private func deviceDetailView(_ device: DeviceInfo) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                // 设备信息卡片
                GroupBox {
                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            Image(systemName: device.deviceType == .simulator ? "desktopcomputer" : "iphone")
                                .font(.title)
                            VStack(alignment: .leading) {
                                Text(device.name)
                                    .font(.title3.bold())
                                Text(device.osVersion)
                                    .foregroundColor(.secondary)
                            }
                            Spacer()
                            StatusBadge(status: device.status)
                        }

                        Divider()

                        Grid(alignment: .leading, horizontalSpacing: 16, verticalSpacing: 6) {
                            GridRow {
                                Text("UDID").foregroundColor(.secondary)
                                Text(device.udid).font(.system(.body, design: .monospaced))
                            }
                            GridRow {
                                Text("类型").foregroundColor(.secondary)
                                Text(device.deviceType.displayName)
                            }
                            GridRow {
                                Text("分辨率").foregroundColor(.secondary)
                                Text(device.resolution)
                            }
                            GridRow {
                                Text("型号").foregroundColor(.secondary)
                                Text(device.modelName)
                            }
                        }
                        .font(.callout)
                    }
                    .padding(4)
                }

                // 模拟器控制
                if device.deviceType == .simulator {
                    GroupBox("模拟器控制") {
                        HStack(spacing: 12) {
                            if device.status == .connected {
                                Button("关闭模拟器") {
                                    Task { await deviceVM.shutdownSimulator(device) }
                                }
                                .tint(.red)
                            } else {
                                Button("启动模拟器") {
                                    Task { await deviceVM.bootSimulator(device) }
                                }
                                .buttonStyle(.borderedProminent)
                            }
                        }
                        .padding(4)
                    }
                }

                // 应用管理
                GroupBox("应用管理") {
                    VStack(alignment: .leading, spacing: 10) {
                        HStack {
                            TextField("Bundle ID (如 com.example.app)", text: $bundleIdInput)
                                .textFieldStyle(.roundedBorder)
                            Button("启动") {
                                Task { await deviceVM.launchApp(bundleId: bundleIdInput) }
                            }
                            .disabled(bundleIdInput.isEmpty)
                            Button("终止") {
                                Task { await deviceVM.terminateApp(bundleId: bundleIdInput) }
                            }
                            .disabled(bundleIdInput.isEmpty)
                        }

                        if device.deviceType == .simulator {
                            HStack {
                                TextField("App 路径 (.app)", text: $appPathInput)
                                    .textFieldStyle(.roundedBorder)
                                Button("选择...") { selectAppFile() }
                                Button("安装") {
                                    Task { await deviceVM.installApp(appPath: appPathInput) }
                                }
                                .disabled(appPathInput.isEmpty)
                            }
                        }
                    }
                    .padding(4)
                }
            }
            .padding()
        }
    }

    private func selectAppFile() {
        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = true
        panel.message = "选择 .app 文件"
        if panel.runModal() == .OK, let url = panel.url {
            appPathInput = url.path
        }
    }
}

// MARK: - 设备行

struct DeviceRow: View {
    let device: DeviceInfo

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: device.deviceType == .simulator ? "desktopcomputer" : "iphone")
                .foregroundColor(device.status == .connected ? .accentColor : .gray)
                .frame(width: 24)

            VStack(alignment: .leading, spacing: 2) {
                Text(device.name)
                    .fontWeight(.medium)
                HStack(spacing: 8) {
                    Text(device.osVersion)
                    Text(device.deviceType.displayName)
                    Text(device.resolution)
                }
                .font(.caption)
                .foregroundColor(.secondary)
            }

            Spacer()
            StatusBadge(status: device.status)
        }
        .padding(.vertical, 2)
    }
}

// MARK: - 状态标签

struct StatusBadge: View {
    let status: DeviceStatus

    var body: some View {
        Text(status.displayName)
            .font(.caption)
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .background(backgroundColor)
            .foregroundColor(.white)
            .clipShape(Capsule())
    }

    private var backgroundColor: Color {
        switch status {
        case .connected: return .green
        case .disconnected: return .gray
        case .booting: return .orange
        case .shuttingDown: return .red
        }
    }
}
