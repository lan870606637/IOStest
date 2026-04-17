import Foundation

// MARK: - 报告生成器
/// 管理测试报告的生成、保存和加载
@MainActor
final class ReportGenerator: ObservableObject {
    static let shared = ReportGenerator()

    @Published var reports: [TestReport] = []
    @Published var currentReport: TestReport?

    private let logger = Logger.shared
    private var currentLoop: LoopReportData?
    private var currentEvent: EventReportData?

    private init() {
        loadReports()
    }

    // MARK: - 报告目录

    private var reportsDirectory: URL {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let dir = appSupport.appendingPathComponent("iOSStressTestTool/reports")
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    // MARK: - 报告生命周期

    /// 开始新报告
    func startReport(taskName: String, deviceUDID: String, deviceName: String) {
        var report = TestReport(taskName: taskName, deviceUDID: deviceUDID, deviceName: deviceName)
        report.startTime = Date()
        report.status = .running
        currentReport = report
        logger.info("开始测试报告: \(report.id)")
    }

    /// 开始新循环
    func startLoop(index: Int) {
        var loop = LoopReportData(loopIndex: index)
        loop.startTime = Date()
        loop.status = .running
        currentLoop = loop
    }

    /// 开始新事件
    func startEvent(_ eventData: EventReportData) {
        var event = eventData
        event.startTime = Date()
        currentEvent = event
    }

    /// 结束当前事件
    func endEvent(status: EventStatus, errorMessage: String? = nil, screenshotPath: String? = nil) {
        guard var event = currentEvent else { return }
        event.endTime = Date()
        event.status = status
        event.errorMessage = errorMessage
        event.screenshotPath = screenshotPath
        if let start = event.startTime {
            event.duration = Date().timeIntervalSince(start)
        }
        currentLoop?.events.append(event)
        currentEvent = nil
    }

    /// 结束当前循环
    func endLoop() {
        guard var loop = currentLoop else { return }
        loop.endTime = Date()
        loop.status = loop.events.contains(where: { $0.status == .failed }) ? .failed : .success
        currentReport?.loops.append(loop)
        currentLoop = nil
    }

    /// 完成报告
    @discardableResult
    func finishReport() -> TestReport? {
        guard var report = currentReport else { return nil }
        report.endTime = Date()
        report.status = report.totalFailedEvents > 0 ? .failed : .success

        // 保存
        saveReport(report)
        reports.insert(report, at: 0)

        logger.info("测试报告完成: \(report.id) - 成功率: \(String(format: "%.1f%%", report.overallSuccessRate))")

        currentReport = nil
        return report
    }

    // MARK: - 持久化

    /// 保存报告到磁盘
    func saveReport(_ report: TestReport) {
        let fileName = "report_\(DateFormatter.fileNameFormatter.string(from: report.startTime ?? Date()))_\(report.id.uuidString.prefix(8)).json"
        let filePath = reportsDirectory.appendingPathComponent(fileName)

        let encoder = JSONEncoder()
        encoder.outputFormatting = .prettyPrinted
        encoder.dateEncodingStrategy = .iso8601

        do {
            let data = try encoder.encode(report)
            try data.write(to: filePath)
            logger.debug("报告已保存: \(filePath.lastPathComponent)")
        } catch {
            logger.error("保存报告失败: \(error)")
        }
    }

    /// 加载所有报告
    func loadReports() {
        let fm = FileManager.default
        guard let files = try? fm.contentsOfDirectory(at: reportsDirectory, includingPropertiesForKeys: [.creationDateKey]) else {
            return
        }

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601

        let loaded = files
            .filter { $0.pathExtension == "json" }
            .compactMap { url -> TestReport? in
                guard let data = try? Data(contentsOf: url) else { return nil }
                return try? decoder.decode(TestReport.self, from: data)
            }
            .sorted { ($0.startTime ?? .distantPast) > ($1.startTime ?? .distantPast) }

        DispatchQueue.main.async {
            self.reports = loaded
        }

        logger.info("已加载 \(loaded.count) 份历史报告")
    }

    /// 删除报告
    func deleteReport(_ report: TestReport) {
        let fm = FileManager.default
        guard let files = try? fm.contentsOfDirectory(at: reportsDirectory, includingPropertiesForKeys: nil) else { return }

        for file in files where file.lastPathComponent.contains(report.id.uuidString.prefix(8)) {
            try? fm.removeItem(at: file)
        }

        reports.removeAll { $0.id == report.id }
    }

    /// 清理旧报告
    func cleanOldReports(keepDays: Int = 30) {
        let cutoff = Calendar.current.date(byAdding: .day, value: -keepDays, to: Date()) ?? Date()
        let toDelete = reports.filter { ($0.startTime ?? Date()) < cutoff }
        for report in toDelete {
            deleteReport(report)
        }
    }

    // MARK: - 导出

    /// 导出报告为 JSON 字符串
    func exportToJSON(_ report: TestReport) -> String? {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        guard let data = try? encoder.encode(report) else { return nil }
        return String(data: data, encoding: .utf8)
    }

    /// 生成 HTML 报告
    func exportToHTML(_ report: TestReport) -> String {
        var html = """
        <!DOCTYPE html>
        <html lang="zh-CN">
        <head>
            <meta charset="UTF-8">
            <title>测试报告 - \(report.taskName)</title>
            <style>
                body { font-family: -apple-system, BlinkMacSystemFont, sans-serif; margin: 40px; background: #f5f5f7; }
                .header { background: #1d1d1f; color: white; padding: 30px; border-radius: 12px; margin-bottom: 20px; }
                .header h1 { margin: 0 0 10px 0; }
                .stats { display: flex; gap: 20px; margin: 20px 0; }
                .stat-card { background: white; padding: 20px; border-radius: 10px; flex: 1; box-shadow: 0 2px 10px rgba(0,0,0,0.1); }
                .stat-value { font-size: 28px; font-weight: bold; color: #0071e3; }
                .stat-label { color: #86868b; margin-top: 5px; }
                .loop { background: white; margin: 10px 0; padding: 15px; border-radius: 8px; box-shadow: 0 1px 4px rgba(0,0,0,0.08); }
                .event { padding: 8px 15px; border-left: 3px solid #0071e3; margin: 5px 0; }
                .event.failed { border-left-color: #ff3b30; background: #fff5f5; }
                .event.success { border-left-color: #34c759; }
                .badge { display: inline-block; padding: 2px 8px; border-radius: 4px; font-size: 12px; }
                .badge.success { background: #34c759; color: white; }
                .badge.failed { background: #ff3b30; color: white; }
            </style>
        </head>
        <body>
            <div class="header">
                <h1>\(report.taskName)</h1>
                <p>设备: \(report.deviceName) | 时长: \(report.formattedDuration) | 开始时间: \(report.startTime?.description ?? "-")</p>
            </div>
            <div class="stats">
                <div class="stat-card">
                    <div class="stat-value">\(report.totalLoops)</div>
                    <div class="stat-label">总循环数</div>
                </div>
                <div class="stat-card">
                    <div class="stat-value">\(report.totalEvents)</div>
                    <div class="stat-label">总事件数</div>
                </div>
                <div class="stat-card">
                    <div class="stat-value">\(String(format: "%.1f%%", report.overallSuccessRate))</div>
                    <div class="stat-label">成功率</div>
                </div>
                <div class="stat-card">
                    <div class="stat-value">\(report.totalFailedEvents)</div>
                    <div class="stat-label">失败事件数</div>
                </div>
            </div>
        """

        for loop in report.loops {
            html += """
            <div class="loop">
                <h3>循环 #\(loop.loopIndex) <span class="badge \(loop.status == .success ? "success" : "failed")">\(loop.status.rawValue)</span></h3>
            """
            for event in loop.events {
                let statusClass = event.status == .success ? "success" : "failed"
                html += """
                <div class="event \(statusClass)">
                    <strong>\(event.eventName)</strong> - \(event.remark)
                    <span class="badge \(statusClass)">\(event.status.rawValue)</span>
                    \(event.errorMessage.map { "<br><small style='color:#ff3b30'>\($0)</small>" } ?? "")
                </div>
                """
            }
            html += "</div>"
        }

        html += "</body></html>"
        return html
    }
}
