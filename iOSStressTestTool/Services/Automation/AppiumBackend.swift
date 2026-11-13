import Foundation
import CoreGraphics

// MARK: - Appium 后端
/// 把 `AutomationBackend` 协议映射到 Appium XCUITest driver 的 HTTP 命令。
final class AppiumBackend: AutomationBackend {
    let kind: AutomationBackendKind = .appium
    let capabilities: BackendCapabilities = .appium

    private let sessions = DeviceSessionManager.shared
    private let logger = Logger.shared

    // MARK: - 会话

    func isReady() async -> Bool {
        do {
            _ = try await AppiumServerManager.shared.ensureRunning()
            return true
        } catch {
            logger.warning("Appium 不可用: \(error.localizedDescription)")
            return false
        }
    }

    func ensureSession(udid: String, bundleId: String?, platformVersion: String?) async throws {
        _ = try await sessions.ensureSession(udid: udid,
                                             bundleId: bundleId,
                                             platformVersion: platformVersion)
    }

    func closeSession(udid: String) async {
        await sessions.closeSession(udid: udid)
    }

    private func context(_ udid: String) async throws -> (client: AppiumClient, sessionId: String) {
        guard let sessionId = await sessions.sessionId(for: udid) else {
            throw AutomationError.sessionUnavailable(udid)
        }
        let client = try await sessions.activeClient()
        return (client, sessionId)
    }

    // MARK: - 坐标操作（单位：point）

    func tap(udid: String, x: Int, y: Int) async throws {
        let (client, sessionId) = try await context(udid)
        _ = try await client.execute(sessionId: sessionId,
                                     script: "mobile: tap",
                                     args: [["x": x, "y": y]])
    }

    func doubleTap(udid: String, x: Int, y: Int) async throws {
        let (client, sessionId) = try await context(udid)
        _ = try await client.execute(sessionId: sessionId,
                                     script: "mobile: doubleTap",
                                     args: [["x": x, "y": y]])
    }

    func longPress(udid: String, x: Int, y: Int, duration: TimeInterval) async throws {
        let (client, sessionId) = try await context(udid)
        _ = try await client.execute(sessionId: sessionId,
                                     script: "mobile: touchAndHold",
                                     args: [["x": x, "y": y, "duration": duration]])
    }

    func swipe(udid: String,
               fromX: Int, fromY: Int,
               toX: Int, toY: Int,
               duration: TimeInterval) async throws {
        let (client, sessionId) = try await context(udid)
        _ = try await client.execute(
            sessionId: sessionId,
            script: "mobile: dragFromToForDuration",
            args: [[
                "fromX": fromX, "fromY": fromY,
                "toX": toX, "toY": toY,
                "duration": duration,
            ]]
        )
    }

    func typeText(udid: String, text: String) async throws {
        let (client, sessionId) = try await context(udid)
        try await client.sendKeys(sessionId: sessionId, text: text)
    }

    func pressButton(udid: String, button: HardwareButton) async throws {
        let (client, sessionId) = try await context(udid)
        _ = try await client.execute(sessionId: sessionId,
                                     script: "mobile: pressButton",
                                     args: [["name": button.appiumName]])
    }

    func alertButtons(udid: String) async throws -> [String] {
        let (client, sessionId) = try await context(udid)
        let value = try await client.execute(sessionId: sessionId,
                                             script: "mobile: alert",
                                             args: [["action": "getButtons"]])
        if let buttons = value as? [String] {
            return buttons
        }
        if let objects = value as? [[String: Any]] {
            return objects.compactMap { $0["name"] as? String ?? $0["label"] as? String }
        }
        return []
    }

    func acceptAlert(udid: String, buttonLabel: String?) async throws {
        let (client, sessionId) = try await context(udid)
        var payload: [String: Any] = ["action": "accept"]
        if let buttonLabel, !buttonLabel.isEmpty {
            payload["buttonLabel"] = buttonLabel
        }
        _ = try await client.execute(sessionId: sessionId,
                                     script: "mobile: alert",
                                     args: [payload])
    }

    func launchApp(udid: String, bundleId: String) async throws {
        let (client, sessionId) = try await context(udid)
        _ = try await client.execute(sessionId: sessionId,
                                     script: "mobile: launchApp",
                                     args: [["bundleId": bundleId]])
    }

    func terminateApp(udid: String, bundleId: String) async throws {
        let (client, sessionId) = try await context(udid)
        _ = try await client.execute(sessionId: sessionId,
                                     script: "mobile: terminateApp",
                                     args: [["bundleId": bundleId]])
    }

    // MARK: - 页面

    func screenshot(udid: String) async throws -> Data {
        let (client, sessionId) = try await context(udid)
        return try await client.screenshot(sessionId: sessionId)
    }

    func source(udid: String) async throws -> String {
        let (client, sessionId) = try await context(udid)
        return try await client.source(sessionId: sessionId)
    }

    // MARK: - 元素

    func findElement(udid: String, locator: Locator) async throws -> ElementHandle? {
        guard locator.isUsable,
              let using = locator.strategy.appiumUsing,
              let value = locator.appiumValue else {
            return nil
        }
        let (client, sessionId) = try await context(udid)
        return try await client.findElement(sessionId: sessionId,
                                            using: using,
                                            value: value,
                                            index: locator.index)
    }

    func click(udid: String, element: ElementHandle) async throws {
        let (client, sessionId) = try await context(udid)
        try await client.click(sessionId: sessionId, element: element)
    }

    func rect(udid: String, element: ElementHandle) async throws -> CGRect {
        let (client, sessionId) = try await context(udid)
        return try await client.rect(sessionId: sessionId, element: element)
    }
}
