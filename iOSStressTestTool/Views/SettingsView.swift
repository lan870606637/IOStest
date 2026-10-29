import SwiftUI

// MARK: - 设置视图
struct SettingsView: View {
    @StateObject private var config = AppConfig.shared

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                Text("设置")
                    .font(.title.bold())
                    .padding(.bottom, 8)

                // 设备设置
                GroupBox("设备设置") {
                    VStack(alignment: .leading, spacing: 12) {
                        settingRow("默认屏幕宽度", value: $config.defaultScreenWidth, range: 320...1366)
                        settingRow("默认屏幕高度", value: $config.defaultScreenHeight, range: 480...1366)
                        settingSlider("截图刷新间隔", value: $config.screenshotRefreshInterval,
                                      range: 0.5...10, unit: "秒")
                        settingSlider("设备轮询间隔", value: $config.devicePollInterval,
                                      range: 1...30, unit: "秒")
                    }
                    .padding(8)
                }

                // 执行设置
                GroupBox("执行设置") {
                    VStack(alignment: .leading, spacing: 12) {
                        settingSlider("默认事件延迟", value: $config.defaultEventDelay,
                                      range: 0...10, unit: "秒")
                        settingRow("重试次数", value: $config.retryCount, range: 0...10)
                        settingSlider("命令超时", value: $config.commandTimeout,
                                      range: 5...120, unit: "秒")
                    }
                    .padding(8)
                }

                // 图像识别设置
                GroupBox("图像识别设置") {
                    VStack(alignment: .leading, spacing: 12) {
                        HStack {
                            Text("默认相似度阈值")
                                .frame(width: 140, alignment: .trailing)
                            Slider(value: Binding(
                                get: { Double(config.defaultSimilarityThreshold) },
                                set: { config.defaultSimilarityThreshold = Int($0) }
                            ), in: 50...100, step: 1)
                            Text("\(config.defaultSimilarityThreshold)%")
                                .frame(width: 40)
                        }
                    }
                    .padding(8)
                }

                // 录制设置
                GroupBox("录制设置") {
                    VStack(alignment: .leading, spacing: 12) {
                        HStack {
                            Text("自动计算延迟")
                                .frame(width: 140, alignment: .trailing)
                            Toggle("", isOn: $config.recordingAutoDelay)
                        }
                        settingSlider("最小录制延迟", value: $config.recordingMinDelay,
                                      range: 0.1...2, unit: "秒")
                        settingSlider("最大录制延迟", value: $config.recordingMaxDelay,
                                      range: 1...30, unit: "秒")
                    }
                    .padding(8)
                }

                // Xcode 设置
                GroupBox("Xcode 设置") {
                    VStack(alignment: .leading, spacing: 12) {
                        HStack {
                            Text("项目路径")
                                .frame(width: 140, alignment: .trailing)
                            TextField("Xcode 项目路径", text: $config.xcodeProjectPath)
                                .textFieldStyle(.roundedBorder)
                            Button("选择...") { selectXcodeProject() }
                        }
                        HStack {
                            Text("测试 Target")
                                .frame(width: 140, alignment: .trailing)
                            TextField("测试 Target 名称", text: $config.testTargetName)
                                .textFieldStyle(.roundedBorder)
                        }
                        HStack {
                            Text("DerivedData")
                                .frame(width: 140, alignment: .trailing)
                            TextField("DerivedData 路径 (可选)", text: $config.derivedDataPath)
                                .textFieldStyle(.roundedBorder)
                            Button("选择...") { selectDerivedData() }
                        }
                    }
                    .padding(8)
                }

                // 日志设置
                GroupBox("日志设置") {
                    VStack(alignment: .leading, spacing: 12) {
                        HStack {
                            Text("日志级别")
                                .frame(width: 140, alignment: .trailing)
                            Picker("", selection: $config.logLevel) {
                                Text("DEBUG").tag("DEBUG")
                                Text("INFO").tag("INFO")
                                Text("WARNING").tag("WARNING")
                                Text("ERROR").tag("ERROR")
                            }
                            .frame(width: 150)
                        }

                        HStack {
                            Spacer()
                            Button("清理旧日志 (>7天)") {
                                Logger.shared.clearOldLogs()
                            }
                            Button("清理旧报告 (>30天)") {
                                ReportGenerator.shared.cleanOldReports()
                            }
                        }
                    }
                    .padding(8)
                }

                // 工具检测
                GroupBox("环境检测") {
                    VStack(alignment: .leading, spacing: 8) {
                        toolCheckRow("Xcode Command Line Tools", path: "/usr/bin/xcrun")
                        toolCheckRow("simctl", path: "/usr/bin/xcrun")
                        goIOSToolRow()
                        libimobiledeviceRow()
                    }
                    .padding(8)
                }

                // 保存按钮
                HStack {
                    Spacer()
                    Button("恢复默认") {
                        let newConfig = AppConfig()
                        config.defaultEventDelay = newConfig.defaultEventDelay
                        config.retryCount = newConfig.retryCount
                        config.commandTimeout = newConfig.commandTimeout
                        config.defaultSimilarityThreshold = newConfig.defaultSimilarityThreshold
                    }
                    Button("保存设置") {
                        config.save()
                    }
                    .buttonStyle(.borderedProminent)
                }
            }
            .padding(20)
        }
    }

    // MARK: - 辅助视图

    private func settingRow(_ label: String, value: Binding<Int>, range: ClosedRange<Int>) -> some View {
        HStack {
            Text(label)
                .frame(width: 140, alignment: .trailing)
            TextField("", value: value, format: .number)
                .textFieldStyle(.roundedBorder)
                .frame(width: 80)
            Stepper("", value: value, in: range)
                .labelsHidden()
        }
    }

    private func settingSlider(_ label: String, value: Binding<Double>, range: ClosedRange<Double>, unit: String) -> some View {
        HStack {
            Text(label)
                .frame(width: 140, alignment: .trailing)
            Slider(value: value, in: range)
            Text(String(format: "%.1f %@", value.wrappedValue, unit))
                .frame(width: 70, alignment: .trailing)
        }
    }

    private func toolCheckRow(_ name: String, path: String) -> some View {
        HStack {
            Image(systemName: ProcessRunner.shared.isToolAvailable(path) ? "checkmark.circle.fill" : "xmark.circle.fill")
                .foregroundColor(ProcessRunner.shared.isToolAvailable(path) ? .green : .red)
            Text(name)
            Spacer()
            Text(path)
                .font(.caption)
                .foregroundColor(.secondary)
        }
    }

    /// go-ios：真机隧道/截图/App 生命周期的主力工具，支持项目内置副本
    private func goIOSToolRow() -> some View {
        let available = GoIOSClient.isToolAvailable
        return HStack {
            Image(systemName: available ? "checkmark.circle.fill" : "xmark.circle.fill")
                .foregroundColor(available ? .green : .red)
            Text("go-ios (真机主力)")
            Spacer()
            Text(GoIOSClient.displayPath)
                .font(.caption)
                .foregroundColor(.secondary)
        }
    }

    /// libimobiledevice：Apple Silicon 在 /opt/homebrew，Intel 在 /usr/local
    private func libimobiledeviceRow() -> some View {
        let runner = ProcessRunner.shared
        let path = ["/opt/homebrew/bin/idevicescreenshot", "/usr/local/bin/idevicescreenshot"]
            .first { runner.isToolAvailable($0) }
        let available = path != nil
        return HStack {
            Image(systemName: available ? "checkmark.circle.fill" : "xmark.circle.fill")
                .foregroundColor(available ? .green : .red)
            Text("libimobiledevice")
            Spacer()
            Text(path ?? "未安装")
                .font(.caption)
                .foregroundColor(.secondary)
        }
    }

    private func selectXcodeProject() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = true
        panel.allowedContentTypes = [.init(filenameExtension: "xcodeproj")!]
        if panel.runModal() == .OK, let url = panel.url {
            config.xcodeProjectPath = url.path
        }
    }

    private func selectDerivedData() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        if panel.runModal() == .OK, let url = panel.url {
            config.derivedDataPath = url.path
        }
    }
}
