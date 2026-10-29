import SwiftUI

// MARK: - 事件编辑器
struct EventEditorView: View {
    @State var event: TestEvent
    @State private var showInspector = false
    let onSave: (TestEvent) -> Void
    let onCancel: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            // 标题栏
            HStack {
                Text("编辑事件")
                    .font(.headline)
                Spacer()
                Button("取消") { onCancel() }
                Button("保存") { onSave(event) }
                    .buttonStyle(.borderedProminent)
            }
            .padding()

            Divider()

            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    // 基本信息
                    GroupBox("基本信息") {
                        VStack(alignment: .leading, spacing: 10) {
                            HStack {
                                Text("事件类型")
                                    .frame(width: 80, alignment: .trailing)
                                Picker("", selection: $event.type) {
                                    ForEach(EventType.allCases) { type in
                                        Text(type.displayName).tag(type)
                                    }
                                }
                                .frame(width: 200)
                            }

                            HStack {
                                Text("备注")
                                    .frame(width: 80, alignment: .trailing)
                                TextField("事件备注", text: $event.remark)
                                    .textFieldStyle(.roundedBorder)
                            }

                            HStack {
                                Text("延迟(秒)")
                                    .frame(width: 80, alignment: .trailing)
                                TextField("", value: $event.delay, format: .number)
                                    .textFieldStyle(.roundedBorder)
                                    .frame(width: 80)
                                Slider(value: $event.delay, in: 0...10, step: 0.1)
                            }

                            HStack {
                                Text("启用")
                                    .frame(width: 80, alignment: .trailing)
                                Toggle("", isOn: $event.isEnabled)
                            }
                        }
                        .padding(8)
                    }

                    // 类型专属参数
                    switch event.type {
                    case .click, .doubleClick, .longPress:
                        VStack(alignment: .leading, spacing: 16) {
                            locatorSection
                            tapParameterSection
                        }
                    case .swipe:
                        swipeParameterSection
                    case .imageRecognitionClick:
                        imageRecognitionSection
                    case .ocrTextClick:
                        ocrSection
                    case .killApp, .launchApp:
                        appManagementSection
                    case .screenshot, .compareScreenshot:
                        screenshotSection
                    case .assertion:
                        assertionSection
                    case .custom:
                        customCommandSection
                    case .eventGroup:
                        eventGroupSection
                    default:
                        EmptyView()
                    }
                }
                .padding()
            }
        }
        .frame(width: 550, height: 500)
        .sheet(isPresented: $showInspector) {
            if let device = DeviceService.shared.selectedDevice {
                ElementInspectorView(deviceUDID: device.udid) { locator, rect in
                    event.locator = locator
                    if event.x == nil { event.x = Int(rect.midX) }
                    if event.y == nil { event.y = Int(rect.midY) }
                }
            } else {
                Text("请先在设备管理中选择设备")
                    .padding()
            }
        }
    }

    // MARK: - 点击参数

    private var tapParameterSection: some View {
        GroupBox("坐标参数") {
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Text("X 坐标")
                        .frame(width: 80, alignment: .trailing)
                    TextField("X", value: $event.x, format: .number)
                        .textFieldStyle(.roundedBorder)
                        .frame(width: 100)

                    Text("Y 坐标")
                        .frame(width: 80, alignment: .trailing)
                    TextField("Y", value: $event.y, format: .number)
                        .textFieldStyle(.roundedBorder)
                        .frame(width: 100)
                }

                if event.type == .longPress {
                    HStack {
                        Text("长按时长")
                            .frame(width: 80, alignment: .trailing)
                        TextField("", value: $event.pressDuration, format: .number)
                            .textFieldStyle(.roundedBorder)
                            .frame(width: 80)
                        Text("秒")
                    }
                }

                Text("提示: 可在屏幕预览中点击获取坐标")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            .padding(8)
        }
    }

    // MARK: - 滑动参数

    private var swipeParameterSection: some View {
        GroupBox("滑动参数") {
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Text("起点 X")
                        .frame(width: 80, alignment: .trailing)
                    TextField("", value: $event.startX, format: .number)
                        .textFieldStyle(.roundedBorder)
                        .frame(width: 80)
                    Text("起点 Y")
                    TextField("", value: $event.startY, format: .number)
                        .textFieldStyle(.roundedBorder)
                        .frame(width: 80)
                }
                HStack {
                    Text("终点 X")
                        .frame(width: 80, alignment: .trailing)
                    TextField("", value: $event.endX, format: .number)
                        .textFieldStyle(.roundedBorder)
                        .frame(width: 80)
                    Text("终点 Y")
                    TextField("", value: $event.endY, format: .number)
                        .textFieldStyle(.roundedBorder)
                        .frame(width: 80)
                }
                HStack {
                    Text("滑动时长")
                        .frame(width: 80, alignment: .trailing)
                    TextField("", value: $event.swipeDuration, format: .number)
                        .textFieldStyle(.roundedBorder)
                        .frame(width: 80)
                    Text("秒")
                }
            }
            .padding(8)
        }
    }

    // MARK: - 图像识别参数

    private var imageRecognitionSection: some View {
        GroupBox("图像识别参数") {
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Text("模板名称")
                        .frame(width: 80, alignment: .trailing)
                    TextField("模板文件名", text: Binding(
                        get: { event.templateName ?? "" },
                        set: { event.templateName = $0.isEmpty ? nil : $0 }
                    ))
                    .textFieldStyle(.roundedBorder)

                    Button("选择...") {
                        selectTemplateFile()
                    }
                }
                HStack {
                    Text("相似度")
                        .frame(width: 80, alignment: .trailing)
                    Slider(value: Binding(
                        get: { Double(event.similarity) },
                        set: { event.similarity = Int($0) }
                    ), in: 50...100, step: 1)
                    Text("\(event.similarity)%")
                        .frame(width: 40)
                }
            }
            .padding(8)
        }
    }

    // MARK: - OCR 参数

    private var ocrSection: some View {
        GroupBox("OCR 文字识别参数") {
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Text("目标文字")
                        .frame(width: 80, alignment: .trailing)
                    TextField("要查找的文字", text: Binding(
                        get: { event.targetText ?? "" },
                        set: { event.targetText = $0.isEmpty ? nil : $0 }
                    ))
                    .textFieldStyle(.roundedBorder)
                }
            }
            .padding(8)
        }
    }

    // MARK: - 应用管理

    private var appManagementSection: some View {
        GroupBox("应用管理") {
            HStack {
                Text("Bundle ID")
                    .frame(width: 80, alignment: .trailing)
                TextField("com.example.app", text: Binding(
                    get: { event.bundleIdentifier ?? "" },
                    set: { event.bundleIdentifier = $0.isEmpty ? nil : $0 }
                ))
                .textFieldStyle(.roundedBorder)
            }
            .padding(8)
        }
    }

    // MARK: - 截图参数

    private var screenshotSection: some View {
        GroupBox("截图参数") {
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Text("截图类型")
                        .frame(width: 80, alignment: .trailing)
                    Picker("", selection: $event.screenshotType) {
                        Text("普通截图").tag(ScreenshotType.normal)
                        Text("对比截图").tag(ScreenshotType.compare)
                    }
                }
                if event.screenshotType == .compare {
                    HStack {
                        Text("对比模板")
                            .frame(width: 80, alignment: .trailing)
                        TextField("模板文件", text: Binding(
                            get: { event.templateName ?? "" },
                            set: { event.templateName = $0.isEmpty ? nil : $0 }
                        ))
                        .textFieldStyle(.roundedBorder)
                    }
                    HStack {
                        Text("相似度")
                            .frame(width: 80, alignment: .trailing)
                        Slider(value: Binding(
                            get: { Double(event.similarity) },
                            set: { event.similarity = Int($0) }
                        ), in: 50...100, step: 1)
                        Text("\(event.similarity)%")
                    }
                }
            }
            .padding(8)
        }
    }

    // MARK: - 断言参数

    private var assertionSection: some View {
        GroupBox("断言参数") {
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Text("断言类型")
                        .frame(width: 80, alignment: .trailing)
                    Picker("", selection: Binding(
                        get: { event.assertType ?? .assertText },
                        set: { event.assertType = $0 }
                    )) {
                        Text("文字断言").tag(AssertType.assertText)
                        Text("图片断言").tag(AssertType.assertImage)
                        Text("UI元素断言").tag(AssertType.assertElement)
                    }
                }
                HStack {
                    Text("断言目标")
                        .frame(width: 80, alignment: .trailing)
                    TextField("断言目标值", text: Binding(
                        get: { event.assertTarget ?? "" },
                        set: { event.assertTarget = $0.isEmpty ? nil : $0 }
                    ))
                    .textFieldStyle(.roundedBorder)
                }
            }
            .padding(8)
        }
    }

    // MARK: - 自定义命令

    private var customCommandSection: some View {
        GroupBox("自定义命令") {
            VStack(alignment: .leading, spacing: 10) {
                Text("Shell 命令")
                    .frame(maxWidth: .infinity, alignment: .leading)
                TextEditor(text: Binding(
                    get: { event.customCommand ?? "" },
                    set: { event.customCommand = $0.isEmpty ? nil : $0 }
                ))
                .font(.system(.body, design: .monospaced))
                .frame(height: 100)
                .border(Color.gray.opacity(0.3))

                Text("支持 xcrun simctl 等 macOS 命令行工具")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            .padding(8)
        }
    }

    // MARK: - 事件组

    private var eventGroupSection: some View {
        GroupBox("事件组设置") {
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Text("执行模式")
                        .frame(width: 80, alignment: .trailing)
                    Picker("", selection: $event.executionMode) {
                        Text("顺序执行").tag(GroupExecutionMode.sequence)
                        Text("并行执行").tag(GroupExecutionMode.parallel)
                    }
                    .pickerStyle(.segmented)
                    .frame(width: 200)
                }
                Text("子事件数: \(event.childEvents?.count ?? 0)")
                    .foregroundColor(.secondary)
            }
            .padding(8)
        }
    }

    // MARK: - 控件定位

    private var locatorEnabled: Binding<Bool> {
        Binding(
            get: { event.locator != nil },
            set: { enabled in
                if enabled {
                    if event.locator == nil {
                        event.locator = Locator()
                    }
                } else {
                    event.locator = nil
                }
            }
        )
    }

    private var locatorStrategy: Binding<LocatorStrategy> {
        Binding(
            get: { event.locator?.strategy ?? .accessibilityId },
            set: { event.locator?.strategy = $0 }
        )
    }

    private var locatorValue: Binding<String> {
        Binding(
            get: { event.locator?.value ?? "" },
            set: { event.locator?.value = $0 }
        )
    }

    private var locatorTimeout: Binding<Double> {
        Binding(
            get: { event.locator?.timeout ?? 5 },
            set: { event.locator?.timeout = $0 }
        )
    }

    private var locatorIndex: Binding<Int> {
        Binding(
            get: { event.locator?.index ?? 0 },
            set: { event.locator?.index = $0 == 0 ? nil : $0 }
        )
    }

    private var locatorSection: some View {
        GroupBox("控件定位（优先于坐标）") {
            VStack(alignment: .leading, spacing: 10) {
                Toggle("使用控件定位", isOn: locatorEnabled)

                HStack {
                    Spacer()
                    Button("从当前页面选择...") { showInspector = true }
                        .disabled(DeviceService.shared.selectedDevice == nil)
                }

                if event.locator != nil {
                    HStack {
                        Text("定位方式")
                            .frame(width: 80, alignment: .trailing)
                        Picker("", selection: locatorStrategy) {
                            ForEach(LocatorStrategy.allCases.filter { $0 != .point }) { strategy in
                                Text(strategy.displayName).tag(strategy)
                            }
                        }
                        .frame(width: 200)
                    }

                    HStack {
                        Text("匹配值")
                            .frame(width: 80, alignment: .trailing)
                        TextField(event.locator?.strategy.placeholder ?? "", text: locatorValue)
                            .textFieldStyle(.roundedBorder)
                    }

                    HStack {
                        Text("超时(秒)")
                            .frame(width: 80, alignment: .trailing)
                        TextField("", value: locatorTimeout, format: .number)
                            .textFieldStyle(.roundedBorder)
                            .frame(width: 80)

                        Text("匹配序号")
                            .frame(width: 80, alignment: .trailing)
                        Stepper(value: locatorIndex, in: 0...20) {
                            Text(locatorIndex.wrappedValue == 0
                                 ? "第一个"
                                 : "第 \(locatorIndex.wrappedValue + 1) 个")
                        }
                    }

                    Text(event.locator?.strategy.helpText ?? "")
                        .font(.caption)
                        .foregroundColor(.secondary)

                    Text("找不到控件时会自动回退到下方坐标。")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }
            .padding(8)
        }
    }

    // MARK: - 辅助方法

    private func selectTemplateFile() {
        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        panel.allowedContentTypes = [.png, .jpeg]
        if panel.runModal() == .OK, let url = panel.url {
            event.templateName = url.lastPathComponent
        }
    }
}
