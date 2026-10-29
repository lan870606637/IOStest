import Foundation
import Darwin

/// P3/P6 集成 smoke：
/// 用真实 EventExecutor 跑「控件定位点击 → 坐标回退 → 报告策略」。
/// 由 scripts/smoke-p3.sh 编译并执行。
@main
@MainActor
struct P3Smoke {
    static func main() async {
        let udid = ProcessInfo.processInfo.environment["SMOKE_UDID"]
            ?? "1C408430-2229-47F2-89C0-76F94BDAF16C"

        do {
            // 1. Locator 编解码 + 旧 JSON 兼容
            var sample = TestEvent(type: .click)
            sample.locator = Locator(strategy: .predicate,
                                     value: "label == \"通用\"",
                                     timeout: 3)
            let encoded = try JSONEncoder().encode(sample)
            let decoded = try JSONDecoder().decode(TestEvent.self, from: encoded)
            print("locator roundtrip:", decoded.locator?.summary ?? "nil")

            var dict = try JSONSerialization.jsonObject(with: encoded) as? [String: Any] ?? [:]
            dict.removeValue(forKey: "locator")
            let stripped = try JSONSerialization.data(withJSONObject: dict)
            let oldEvent = try JSONDecoder().decode(TestEvent.self, from: stripped)
            print("old json locator:", oldEvent.locator == nil ? "nil (OK)" : "non-nil (BAD)")

            // 2. 建会话
            let backend = AppiumBackend()
            try await backend.ensureSession(udid: udid,
                                            bundleId: "com.apple.Preferences",
                                            platformVersion: "26.5")
            print("session ready")

            let report = ReportGenerator.shared
            report.startReport(taskName: "P3 Smoke", deviceUDID: udid, deviceName: "iPhone 17 Pro")
            report.startLoop(index: 1)

            // 3. locator 点击（坐标故意写错，验证控件优先）
            var locatorClick = TestEvent(type: .click)
            locatorClick.remark = "locator click"
            locatorClick.locator = Locator(strategy: .predicate,
                                           value: "label == \"通用\"",
                                           timeout: 5)
            locatorClick.x = 1
            locatorClick.y = 1
            let first = await EventExecutor.shared.executeEvent(locatorClick, deviceUDID: udid)
            print("locator click:", first.0.rawValue, first.1 ?? "")
            let source1 = try await backend.source(udid: udid)
            print("entered general:", source1.contains("关于本机"))

            // 4. 坐标回退：返回按钮中心 (38, 84)
            var coordinateClick = TestEvent(type: .click)
            coordinateClick.remark = "coordinate back"
            coordinateClick.x = 38
            coordinateClick.y = 84
            let second = await EventExecutor.shared.executeEvent(coordinateClick, deviceUDID: udid)
            print("coordinate click:", second.0.rawValue, second.1 ?? "")
            let source2 = try await backend.source(udid: udid)
            print("back to root:", !source2.contains("关于本机"))

            // 5. 报告策略
            report.endLoop()
            let finished = report.finishReport()
            for event in finished?.loops.first?.events ?? [] {
                print("report:", event.remark,
                      event.status.rawValue,
                      "strategy=", event.strategy ?? "nil")
            }

            await backend.closeSession(udid: udid)
            await AppiumServerManager.shared.stop()
            print("P3 SMOKE OK")
            exit(0)
        } catch {
            print("P3 SMOKE FAILED:", error.localizedDescription)
            await AppiumServerManager.shared.stop()
            exit(1)
        }
    }
}
