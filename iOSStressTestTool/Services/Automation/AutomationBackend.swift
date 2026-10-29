import Foundation
import CoreGraphics

// MARK: - 自动化后端抽象

enum AutomationBackendKind: String, Codable {
    case appium
    case legacyCLI

    var displayName: String {
        switch self {
        case .appium: return "Appium (XCUITest)"
        case .legacyCLI: return "CLI (simctl/go-ios)"
        }
    }
}

struct BackendCapabilities: Equatable {
    var supportsElementLookup: Bool
    var supportsCoordinates: Bool
    var supportsScreenshot: Bool
    var supportsHardwareButtons: Bool
    var supportsTextInput: Bool

    static let appium = BackendCapabilities(
        supportsElementLookup: true,
        supportsCoordinates: true,
        supportsScreenshot: true,
        supportsHardwareButtons: true,
        supportsTextInput: true
    )

    static let legacyCLI = BackendCapabilities(
        supportsElementLookup: false,
        supportsCoordinates: true,
        supportsScreenshot: true,
        supportsHardwareButtons: true,
        supportsTextInput: true
    )
}

/// Appium 返回的 element id（W3C 的 `element-6066-...` 或旧的 `ELEMENT`）。
struct ElementHandle: Codable, Hashable {
    let id: String
}

enum HardwareButton: String, CaseIterable {
    case home
    case lock
    case volumeUp
    case volumeDown

    var displayName: String {
        switch self {
        case .home: return "Home"
        case .lock: return "锁屏"
        case .volumeUp: return "音量+"
        case .volumeDown: return "音量-"
        }
    }

    /// WDA `mobile: pressButton` 使用的名字。
    var appiumName: String {
        switch self {
        case .home: return "home"
        case .lock: return "lock"
        case .volumeUp: return "volumeUp"
        case .volumeDown: return "volumeDown"
        }
    }
}

// MARK: - 错误

enum AutomationError: LocalizedError {
    case backendUnavailable(String)
    case sessionUnavailable(String)
    case elementNotFound(String)
    case commandFailed(String)
    case invalidResponse(String)
    case timeout(String)

    var errorDescription: String? {
        switch self {
        case .backendUnavailable(let message):
            return "自动化后端不可用：\(message)"
        case .sessionUnavailable(let udid):
            return "设备 \(udid) 没有可用的自动化会话"
        case .elementNotFound(let detail):
            return "未找到控件：\(detail)"
        case .commandFailed(let message):
            return "命令执行失败：\(message)"
        case .invalidResponse(let message):
            return "后端返回了无法解析的响应：\(message)"
        case .timeout(let message):
            return "操作超时：\(message)"
        }
    }
}

// MARK: - 协议

protocol AutomationBackend: AnyObject {
    var kind: AutomationBackendKind { get }
    var capabilities: BackendCapabilities { get }

    func isReady() async -> Bool

    func ensureSession(udid: String, bundleId: String?, platformVersion: String?) async throws
    func closeSession(udid: String) async

    func tap(udid: String, x: Int, y: Int) async throws
    func doubleTap(udid: String, x: Int, y: Int) async throws
    func longPress(udid: String, x: Int, y: Int, duration: TimeInterval) async throws
    func swipe(udid: String, fromX: Int, fromY: Int, toX: Int, toY: Int, duration: TimeInterval) async throws
    func typeText(udid: String, text: String) async throws
    func pressButton(udid: String, button: HardwareButton) async throws

    func launchApp(udid: String, bundleId: String) async throws
    func terminateApp(udid: String, bundleId: String) async throws

    func screenshot(udid: String) async throws -> Data
    func source(udid: String) async throws -> String

    func findElement(udid: String, locator: Locator) async throws -> ElementHandle?
    func click(udid: String, element: ElementHandle) async throws
    func rect(udid: String, element: ElementHandle) async throws -> CGRect
}
