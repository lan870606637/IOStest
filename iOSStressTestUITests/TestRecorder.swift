import XCTest

/// XCUITest 端事件录制辅助
/// 配合 macOS 控制端录制功能，在设备端捕获和回放事件
/// 注意: XCUITest 本身支持 Xcode 的录制功能 (Record UI Test)
///       该类提供编程方式的录制补充
final class TestRecorder: XCTestCase {

    private var app: XCUIApplication!
    private var recordedActions: [RecordedAction] = []
    private var isRecording = false
    private var startTime: Date?

    // MARK: - 录制数据结构

    struct RecordedAction: Codable {
        let timestamp: TimeInterval  // 相对于录制开始的时间
        let type: String
        let x: CGFloat?
        let y: CGFloat?
        let endX: CGFloat?
        let endY: CGFloat?
        let duration: Double?
        let elementLabel: String?
        let description: String
    }

    // MARK: - Setup

    override func setUpWithError() throws {
        continueAfterFailure = true

        let bundleID = ProcessInfo.processInfo.environment["STRESS_TEST_BUNDLE_ID"] ?? ""
        if !bundleID.isEmpty {
            app = XCUIApplication(bundleIdentifier: bundleID)
        } else {
            app = XCUIApplication()
        }
        app.launch()
    }

    override func tearDownWithError() throws {
        if isRecording {
            stopRecording()
        }
        app?.terminate()
    }

    // MARK: - 录制辅助测试

    /// 该测试方法启动后保持运行，等待 macOS 控制端发送操作指令
    /// 通过环境变量或文件通信接收事件指令
    func testRecordingSession() {
        let sessionDuration = TimeInterval(
            ProcessInfo.processInfo.environment["STRESS_TEST_RECORD_DURATION"] ?? "300"
        ) ?? 300

        startRecording()

        // 保持会话运行
        let expectation = XCTestExpectation(description: "录制会话")
        DispatchQueue.global().asyncAfter(deadline: .now() + sessionDuration) {
            expectation.fulfill()
        }

        wait(for: [expectation], timeout: sessionDuration + 10)
        stopRecording()
    }

    /// 从文件回放录制的事件
    func testPlaybackFromFile() {
        let filePath = ProcessInfo.processInfo.environment["STRESS_TEST_PLAYBACK_FILE"] ?? ""
        guard !filePath.isEmpty,
              let data = FileManager.default.contents(atPath: filePath),
              let actions = try? JSONDecoder().decode([RecordedAction].self, from: data) else {
            XCTFail("无法加载回放文件")
            return
        }

        print("开始回放 \(actions.count) 个录制事件")
        let player = EventPlayer(app: app)
        var previousTimestamp: TimeInterval = 0

        for (index, action) in actions.enumerated() {
            // 等待与上一事件的时间间隔
            let interval = action.timestamp - previousTimestamp
            if interval > 0 {
                Thread.sleep(forTimeInterval: min(interval, 5.0))
            }

            print("回放事件 \(index + 1)/\(actions.count): \(action.description)")

            switch action.type {
            case "tap":
                if let x = action.x, let y = action.y {
                    player.tap(at: CGPoint(x: x, y: y))
                }
            case "double_tap":
                if let x = action.x, let y = action.y {
                    player.doubleTap(at: CGPoint(x: x, y: y))
                }
            case "long_press":
                if let x = action.x, let y = action.y {
                    player.longPress(at: CGPoint(x: x, y: y), duration: action.duration ?? 1.0)
                }
            case "swipe":
                if let x = action.x, let y = action.y,
                   let ex = action.endX, let ey = action.endY {
                    player.swipe(from: CGPoint(x: x, y: y), to: CGPoint(x: ex, y: ey))
                }
            case "home":
                player.pressHome()
            case "volume_up":
                player.pressVolumeUp()
            case "volume_down":
                player.pressVolumeDown()
            case "text_tap":
                if let label = action.elementLabel {
                    _ = player.tapElement(withText: label)
                }
            default:
                print("未知操作: \(action.type)")
            }

            previousTimestamp = action.timestamp
        }

        print("回放完成")
    }

    // MARK: - 录制控制

    private func startRecording() {
        recordedActions.removeAll()
        startTime = Date()
        isRecording = true
        print("XCUITest 录制开始")
    }

    private func stopRecording() {
        isRecording = false
        saveRecording()
        print("XCUITest 录制结束，共 \(recordedActions.count) 个事件")
    }

    /// 记录操作 (由外部调用)
    func record(action: RecordedAction) {
        guard isRecording else { return }
        recordedActions.append(action)
    }

    // MARK: - 持久化

    private func saveRecording() {
        guard !recordedActions.isEmpty else { return }

        let encoder = JSONEncoder()
        encoder.outputFormatting = .prettyPrinted

        guard let data = try? encoder.encode(recordedActions) else {
            print("录制数据编码失败")
            return
        }

        // 保存到 DerivedData 或临时目录
        let outputPath = ProcessInfo.processInfo.environment["STRESS_TEST_RECORD_OUTPUT"]
            ?? NSTemporaryDirectory() + "recorded_actions.json"

        FileManager.default.createFile(atPath: outputPath, contents: data)
        print("录制数据已保存: \(outputPath)")

        // 同时作为测试附件保存
        let attachment = XCTAttachment(data: data, uniformTypeIdentifier: "public.json")
        attachment.name = "recorded_actions.json"
        attachment.lifetime = .keepAlways
        add(attachment)
    }

    // MARK: - 辅助: 获取当前屏幕元素树

    /// 打印当前 UI 元素树 (调试用)
    func testDumpUIHierarchy() {
        print("=== UI 元素树 ===")
        print(app.debugDescription)
        print("=== 元素树结束 ===")

        // 保存为附件
        let data = app.debugDescription.data(using: .utf8) ?? Data()
        let attachment = XCTAttachment(data: data, uniformTypeIdentifier: "public.plain-text")
        attachment.name = "ui_hierarchy.txt"
        attachment.lifetime = .keepAlways
        add(attachment)
    }

    /// 列出所有可交互元素
    func testListInteractableElements() {
        var elements: [[String: String]] = []

        let types: [XCUIElement.ElementType] = [.button, .textField, .staticText, .cell, .switch, .slider]

        for type in types {
            let query = app.descendants(matching: type)
            for i in 0..<query.count {
                let element = query.element(boundBy: i)
                if element.exists && element.isHittable {
                    elements.append([
                        "type": "\(type)",
                        "label": element.label,
                        "identifier": element.identifier,
                        "frame": "\(element.frame)"
                    ])
                }
            }
        }

        print("可交互元素: \(elements.count) 个")
        for (index, el) in elements.enumerated() {
            print("  [\(index)] \(el["type"] ?? "") | label=\(el["label"] ?? "") | id=\(el["identifier"] ?? "") | frame=\(el["frame"] ?? "")")
        }
    }
}
