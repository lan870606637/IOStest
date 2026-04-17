import XCTest

/// 事件播放器
/// 封装 XCUITest API 提供统一的事件回放接口
final class EventPlayer {
    let app: XCUIApplication

    init(app: XCUIApplication) {
        self.app = app
    }

    // MARK: - 点击操作

    func tap(at point: CGPoint) {
        let coordinate = app.coordinate(withNormalizedOffset: .zero)
            .withOffset(CGVector(dx: point.x, dy: point.y))
        coordinate.tap()
    }

    func doubleTap(at point: CGPoint) {
        let coordinate = app.coordinate(withNormalizedOffset: .zero)
            .withOffset(CGVector(dx: point.x, dy: point.y))
        coordinate.doubleTap()
    }

    func longPress(at point: CGPoint, duration: TimeInterval) {
        let coordinate = app.coordinate(withNormalizedOffset: .zero)
            .withOffset(CGVector(dx: point.x, dy: point.y))
        coordinate.press(forDuration: duration)
    }

    // MARK: - 滑动操作

    func swipe(from start: CGPoint, to end: CGPoint, duration: TimeInterval = 0.5) {
        let startCoord = app.coordinate(withNormalizedOffset: .zero)
            .withOffset(CGVector(dx: start.x, dy: start.y))
        let endCoord = app.coordinate(withNormalizedOffset: .zero)
            .withOffset(CGVector(dx: end.x, dy: end.y))

        startCoord.press(forDuration: 0.05, thenDragTo: endCoord)
    }

    func swipeUp(from point: CGPoint? = nil, distance: CGFloat = 200) {
        let origin = point ?? CGPoint(x: app.frame.midX, y: app.frame.midY)
        swipe(from: origin, to: CGPoint(x: origin.x, y: origin.y - distance))
    }

    func swipeDown(from point: CGPoint? = nil, distance: CGFloat = 200) {
        let origin = point ?? CGPoint(x: app.frame.midX, y: app.frame.midY)
        swipe(from: origin, to: CGPoint(x: origin.x, y: origin.y + distance))
    }

    func swipeLeft(from point: CGPoint? = nil, distance: CGFloat = 200) {
        let origin = point ?? CGPoint(x: app.frame.midX, y: app.frame.midY)
        swipe(from: origin, to: CGPoint(x: origin.x - distance, y: origin.y))
    }

    func swipeRight(from point: CGPoint? = nil, distance: CGFloat = 200) {
        let origin = point ?? CGPoint(x: app.frame.midX, y: app.frame.midY)
        swipe(from: origin, to: CGPoint(x: origin.x + distance, y: origin.y))
    }

    // MARK: - 硬件按钮

    func pressHome() {
        XCUIDevice.shared.press(.home)
    }

    func pressVolumeUp() {
        XCUIDevice.shared.press(.volumeUp)
    }

    func pressVolumeDown() {
        XCUIDevice.shared.press(.volumeDown)
    }

    // MARK: - 元素操作

    /// 查找并点击包含指定文字的元素
    func tapElement(withText text: String, timeout: TimeInterval = 5) -> Bool {
        let predicate = NSPredicate(format: "label CONTAINS[cd] %@", text)
        let element = app.descendants(matching: .any).matching(predicate).firstMatch

        if element.waitForExistence(timeout: timeout) {
            element.tap()
            return true
        }
        return false
    }

    /// 查找并点击指定 accessibilityIdentifier 的元素
    func tapElement(withIdentifier identifier: String, timeout: TimeInterval = 5) -> Bool {
        let element = app.descendants(matching: .any)[identifier]
        if element.waitForExistence(timeout: timeout) {
            element.tap()
            return true
        }
        return false
    }

    /// 在文本框中输入文字
    func typeText(_ text: String, in element: XCUIElement) {
        if element.waitForExistence(timeout: 3) {
            element.tap()
            element.typeText(text)
        }
    }

    /// 清空并输入文字
    func clearAndType(_ text: String, in element: XCUIElement) {
        if element.waitForExistence(timeout: 3) {
            element.tap()
            // 全选并删除
            element.press(forDuration: 1.0)
            let selectAll = app.menuItems["Select All"]
            if selectAll.waitForExistence(timeout: 1) {
                selectAll.tap()
            }
            element.typeText(text)
        }
    }

    // MARK: - 截图

    func takeScreenshot(name: String = "screenshot") -> XCTAttachment {
        let screenshot = XCUIScreen.main.screenshot()
        let attachment = XCTAttachment(screenshot: screenshot)
        attachment.name = name
        attachment.lifetime = .keepAlways
        return attachment
    }

    // MARK: - 等待

    func wait(seconds: TimeInterval) {
        Thread.sleep(forTimeInterval: seconds)
    }

    /// 等待元素出现
    func waitForElement(withText text: String, timeout: TimeInterval = 10) -> Bool {
        let predicate = NSPredicate(format: "label CONTAINS[cd] %@", text)
        let element = app.descendants(matching: .any).matching(predicate).firstMatch
        return element.waitForExistence(timeout: timeout)
    }

    /// 等待元素消失
    func waitForElementToDisappear(withText text: String, timeout: TimeInterval = 10) -> Bool {
        let predicate = NSPredicate(format: "label CONTAINS[cd] %@", text)
        let element = app.descendants(matching: .any).matching(predicate).firstMatch

        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if !element.exists { return true }
            Thread.sleep(forTimeInterval: 0.5)
        }
        return !element.exists
    }
}
