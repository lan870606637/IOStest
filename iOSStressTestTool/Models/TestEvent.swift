import Foundation

// MARK: - 事件类型
enum EventType: String, Codable, CaseIterable, Identifiable {
    case click = "click"
    case doubleClick = "double_click"
    case longPress = "long_press"
    case swipe = "swipe"
    case imageRecognitionClick = "image_recognition_click"
    case ocrTextClick = "ocr_text_click"
    case popupButton = "popup_button"
    case screenshot = "screenshot"
    case compareScreenshot = "compare_screenshot"
    case killApp = "kill_app"
    case launchApp = "launch_app"
    case custom = "custom"
    case assertion = "assert"
    case eventGroup = "event_group"
    case homeButton = "home_button"
    case volumeUp = "volume_up"
    case volumeDown = "volume_down"
    case lockScreen = "lock_screen"
    case shake = "shake"

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .click: return "单击"
        case .doubleClick: return "双击"
        case .longPress: return "长按"
        case .swipe: return "滑动"
        case .imageRecognitionClick: return "图像识别点击"
        case .ocrTextClick: return "OCR文字点击"
        case .popupButton: return "弹窗按钮"
        case .screenshot: return "截图"
        case .compareScreenshot: return "对比截图"
        case .killApp: return "终止应用"
        case .launchApp: return "启动应用"
        case .custom: return "自定义命令"
        case .assertion: return "断言"
        case .eventGroup: return "事件组"
        case .homeButton: return "Home键"
        case .volumeUp: return "音量+"
        case .volumeDown: return "音量-"
        case .lockScreen: return "锁屏"
        case .shake: return "摇晃"
        }
    }

    var isRecordable: Bool {
        switch self {
        case .click, .doubleClick, .longPress, .swipe,
             .homeButton, .volumeUp, .volumeDown, .lockScreen, .shake:
            return true
        default:
            return false
        }
    }
}

// MARK: - 断言类型
enum AssertType: String, Codable {
    case assertText = "assert_text"
    case assertImage = "assert_image"
    case assertElement = "assert_element"

    var displayName: String {
        switch self {
        case .assertText: return "断言文字"
        case .assertImage: return "断言图片"
        case .assertElement: return "断言UI元素"
        }
    }
}

// MARK: - 事件组执行模式
enum GroupExecutionMode: String, Codable {
    case sequence = "sequence"
    case parallel = "parallel"

    var displayName: String {
        switch self {
        case .sequence: return "顺序执行"
        case .parallel: return "并行执行"
        }
    }
}

// MARK: - 截图类型
enum ScreenshotType: String, Codable {
    case normal = "normal"
    case none = "none"
    case compare = "compare"
}

// MARK: - 事件执行状态
enum EventStatus: String, Codable {
    case pending = "pending"
    case running = "running"
    case success = "success"
    case failed = "failed"
    case skipped = "skipped"
}

// MARK: - 测试事件模型
struct TestEvent: Identifiable, Codable {
    var id: UUID = UUID()
    var type: EventType
    var remark: String = ""
    var delay: Double = 1.0
    var isEnabled: Bool = true

    // 坐标 (用于 click, doubleClick, longPress)
    var x: Int?
    var y: Int?

    /// 控件定位，优先于坐标；旧任务没有该字段时为 nil
    var locator: Locator?

    // 滑动参数
    var startX: Int?
    var startY: Int?
    var endX: Int?
    var endY: Int?
    var swipeDuration: Double = 0.5

    // 长按时长
    var pressDuration: Double = 1.0

    // 图像识别参数
    var templateName: String?
    var similarity: Int = 80

    // OCR 参数
    var targetText: String?

    // 弹窗按钮参数（可选，兼容旧 JSON）
    var popupButtonText: String?
    var popupTimeout: Double?
    var popupInterval: Double?

    // 截图参数
    var screenshotType: ScreenshotType = .none

    // 应用管理
    var bundleIdentifier: String?

    // 自定义命令
    var customCommand: String?

    // 断言参数
    var assertType: AssertType?
    var assertTarget: String?

    // 事件组
    var executionMode: GroupExecutionMode = .sequence
    var childEvents: [TestEvent]?

    // 设备信息
    var deviceUDID: String?
    var resolution: String?

    // 录制时间戳
    var recordedAt: Date?
}

// MARK: - 录制的原始事件
struct RecordedRawEvent: Identifiable {
    let id = UUID()
    let timestamp: Date
    let type: EventType
    let x: Int?
    let y: Int?
    let startX: Int?
    let startY: Int?
    let endX: Int?
    let endY: Int?
    let duration: Double?
    let description: String
}
