import XCTest

/// XCUITest 压测运行器
/// 从 JSON 文件加载测试事件并在真机/模拟器上执行
/// 这是设备端测试的入口，由 macOS 控制端通过 xcodebuild test 启动
final class StressTestRunner: XCTestCase {

    private var app: XCUIApplication!
    private var taskData: TaskPayload?

    // MARK: - 测试配置

    /// 从环境变量读取要执行的任务文件路径
    private var taskFilePath: String {
        ProcessInfo.processInfo.environment["STRESS_TEST_TASK_FILE"] ?? ""
    }

    /// 目标应用的 Bundle ID
    private var targetBundleID: String {
        ProcessInfo.processInfo.environment["STRESS_TEST_BUNDLE_ID"] ?? ""
    }

    /// 循环次数 (可通过环境变量覆盖)
    private var loopCount: Int {
        Int(ProcessInfo.processInfo.environment["STRESS_TEST_LOOP_COUNT"] ?? "") ?? 1
    }

    // MARK: - Setup / Teardown

    override func setUpWithError() throws {
        continueAfterFailure = true

        // 加载任务数据
        if !taskFilePath.isEmpty {
            taskData = loadTaskData(from: taskFilePath)
        }

        // 启动目标应用
        if !targetBundleID.isEmpty {
            app = XCUIApplication(bundleIdentifier: targetBundleID)
            app.launch()
        } else {
            app = XCUIApplication()
            app.launch()
        }
    }

    override func tearDownWithError() throws {
        app?.terminate()
    }

    // MARK: - 测试入口

    /// 从文件加载并执行所有事件
    func testExecuteTaskFromFile() throws {
        guard let task = taskData else {
            XCTFail("无法加载任务数据，请设置环境变量 STRESS_TEST_TASK_FILE")
            return
        }

        for loop in 1...loopCount {
            print("--- 循环 \(loop)/\(loopCount) ---")

            for (index, event) in task.events.enumerated() {
                guard event.isEnabled else { continue }

                print("[\(loop)/\(loopCount)] 事件 \(index + 1)/\(task.events.count): \(event.type) - \(event.remark)")

                executeEvent(event)

                if event.delay > 0 {
                    Thread.sleep(forTimeInterval: event.delay)
                }
            }
        }
    }

    /// 基本压测: 反复执行点击操作
    func testBasicStress() {
        let loops = loopCount
        for i in 1...loops {
            print("压测循环: \(i)/\(loops)")

            // 随机点击屏幕中心区域
            let centerX = app.frame.midX
            let centerY = app.frame.midY
            let coordinate = app.coordinate(withNormalizedOffset: CGVector(
                dx: 0.5 + Double.random(in: -0.2...0.2),
                dy: 0.5 + Double.random(in: -0.2...0.2)
            ))
            coordinate.tap()

            Thread.sleep(forTimeInterval: 0.5)
        }
    }

    // MARK: - 事件执行

    private func executeEvent(_ event: EventPayload) {
        switch event.type {
        case "click":
            executeTap(x: event.x ?? 0, y: event.y ?? 0)

        case "double_click":
            executeDoubleTap(x: event.x ?? 0, y: event.y ?? 0)

        case "long_press":
            executeLongPress(x: event.x ?? 0, y: event.y ?? 0, duration: event.pressDuration ?? 1.0)

        case "swipe":
            executeSwipe(
                startX: event.startX ?? 0, startY: event.startY ?? 0,
                endX: event.endX ?? 0, endY: event.endY ?? 0,
                duration: event.swipeDuration ?? 0.5
            )

        case "home_button":
            XCUIDevice.shared.press(.home)

        case "volume_up":
            // 音量键 API 在模拟器上不可用，仅真机支持
            #if targetEnvironment(simulator)
            print("音量加：模拟器不支持 XCUIDevice 音量键，已跳过（真机可用）")
            #else
            XCUIDevice.shared.press(.volumeUp)
            #endif

        case "volume_down":
            #if targetEnvironment(simulator)
            print("音量减：模拟器不支持 XCUIDevice 音量键，已跳过（真机可用）")
            #else
            XCUIDevice.shared.press(.volumeDown)
            #endif

        case "screenshot":
            let screenshot = XCUIScreen.main.screenshot()
            let attachment = XCTAttachment(screenshot: screenshot)
            attachment.name = event.remark.isEmpty ? "screenshot_\(Date())" : event.remark
            attachment.lifetime = .keepAlways
            add(attachment)

        case "launch_app":
            if let bundleId = event.bundleIdentifier {
                let targetApp = XCUIApplication(bundleIdentifier: bundleId)
                targetApp.launch()
            }

        case "kill_app":
            if let bundleId = event.bundleIdentifier {
                let targetApp = XCUIApplication(bundleIdentifier: bundleId)
                targetApp.terminate()
            }

        case "assert":
            executeAssertion(event)

        case "ocr_text_click":
            if let text = event.targetText {
                executeTextTap(text: text)
            }

        case "shake":
            // XCUIDevice doesn't directly support shake in automation
            // Use a workaround via coordinate gestures
            print("Shake 事件需要通过 simctl 实现")

        default:
            print("未知事件类型: \(event.type)")
        }
    }

    // MARK: - 坐标操作

    private func executeTap(x: Int, y: Int) {
        let normalized = normalizeCoordinate(x: x, y: y)
        let coordinate = app.coordinate(withNormalizedOffset: CGVector(dx: 0, dy: 0))
            .withOffset(CGVector(dx: CGFloat(x), dy: CGFloat(y)))
        coordinate.tap()
    }

    private func executeDoubleTap(x: Int, y: Int) {
        let coordinate = app.coordinate(withNormalizedOffset: CGVector(dx: 0, dy: 0))
            .withOffset(CGVector(dx: CGFloat(x), dy: CGFloat(y)))
        coordinate.doubleTap()
    }

    private func executeLongPress(x: Int, y: Int, duration: Double) {
        let coordinate = app.coordinate(withNormalizedOffset: CGVector(dx: 0, dy: 0))
            .withOffset(CGVector(dx: CGFloat(x), dy: CGFloat(y)))
        coordinate.press(forDuration: duration)
    }

    private func executeSwipe(startX: Int, startY: Int, endX: Int, endY: Int, duration: Double) {
        let start = app.coordinate(withNormalizedOffset: CGVector(dx: 0, dy: 0))
            .withOffset(CGVector(dx: CGFloat(startX), dy: CGFloat(startY)))
        let end = app.coordinate(withNormalizedOffset: CGVector(dx: 0, dy: 0))
            .withOffset(CGVector(dx: CGFloat(endX), dy: CGFloat(endY)))
        start.press(forDuration: 0.05, thenDragTo: end, withVelocity: .default, thenHoldForDuration: 0.1)
    }

    // MARK: - 文本操作

    private func executeTextTap(text: String) {
        // 尝试查找包含目标文字的元素
        let predicate = NSPredicate(format: "label CONTAINS[cd] %@", text)
        let element = app.descendants(matching: .any).matching(predicate).firstMatch

        if element.waitForExistence(timeout: 5) {
            element.tap()
            print("找到并点击文字元素: \(text)")
        } else {
            print("未找到文字元素: \(text)")
            XCTFail("OCR 文字未找到: \(text)")
        }
    }

    // MARK: - 断言

    private func executeAssertion(_ event: EventPayload) {
        guard let assertType = event.assertType, let target = event.assertTarget else {
            XCTFail("断言参数不完整")
            return
        }

        switch assertType {
        case "assert_text":
            let predicate = NSPredicate(format: "label CONTAINS[cd] %@", target)
            let element = app.descendants(matching: .any).matching(predicate).firstMatch
            XCTAssertTrue(element.waitForExistence(timeout: 5), "断言失败: 未找到文字 '\(target)'")

        case "assert_element":
            let element = app.descendants(matching: .any)[target]
            XCTAssertTrue(element.waitForExistence(timeout: 5), "断言失败: 未找到UI元素 '\(target)'")

        case "assert_image":
            // 截图并保存用于后续对比
            let screenshot = XCUIScreen.main.screenshot()
            let attachment = XCTAttachment(screenshot: screenshot)
            attachment.name = "assert_\(target)"
            attachment.lifetime = .keepAlways
            add(attachment)

        default:
            print("未知断言类型: \(assertType)")
        }
    }

    // MARK: - 辅助方法

    private func normalizeCoordinate(x: Int, y: Int) -> CGVector {
        let screenSize = XCUIScreen.main.screenshot().image.size
        return CGVector(
            dx: CGFloat(x) / screenSize.width,
            dy: CGFloat(y) / screenSize.height
        )
    }

    private func loadTaskData(from path: String) -> TaskPayload? {
        guard let data = FileManager.default.contents(atPath: path) else {
            print("无法读取任务文件: \(path)")
            return nil
        }
        return try? JSONDecoder().decode(TaskPayload.self, from: data)
    }
}

// MARK: - 数据传输结构 (轻量化，用于 XCUITest 端)

struct TaskPayload: Codable {
    let name: String
    let loopCount: Int
    let events: [EventPayload]
}

struct EventPayload: Codable {
    let type: String
    let remark: String
    let delay: Double
    let isEnabled: Bool

    var x: Int?
    var y: Int?
    var startX: Int?
    var startY: Int?
    var endX: Int?
    var endY: Int?
    var swipeDuration: Double?
    var pressDuration: Double?
    var templateName: String?
    var similarity: Int?
    var targetText: String?
    var bundleIdentifier: String?
    var customCommand: String?
    var assertType: String?
    var assertTarget: String?
}
