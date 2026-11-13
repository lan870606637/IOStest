import SwiftUI
import AppKit

// MARK: - 报告视图
struct ReportView: View {
    @StateObject private var reportGenerator = ReportGenerator.shared

    @State private var selectedReport: TestReport?
    @State private var expandedLoops: Set<UUID> = []

    var body: some View {
        HSplitView {
            // 报告列表
            VStack(spacing: 0) {
                HStack {
                    Text("测试报告")
                        .font(.headline)
                    Spacer()
                    Button(action: { reportGenerator.loadReports() }) {
                        Image(systemName: "arrow.clockwise")
                    }
                }
                .padding(10)
                .background(Color(nsColor: .controlBackgroundColor))

                Divider()

                if reportGenerator.reports.isEmpty {
                    VStack {
                        Image(systemName: "doc.text")
                            .font(.system(size: 36))
                            .foregroundColor(.secondary)
                        Text("暂无报告")
                            .foregroundColor(.secondary)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    List(reportGenerator.reports, selection: Binding(
                        get: { selectedReport?.id },
                        set: { id in selectedReport = reportGenerator.reports.first { $0.id == id } }
                    )) { report in
                        ReportListRow(report: report)
                            .tag(report.id)
                            .contextMenu {
                                Button("导出 HTML") { exportHTML(report) }
                                Button("导出 JSON") { exportJSON(report) }
                                Divider()
                                Button("删除", role: .destructive) {
                                    reportGenerator.deleteReport(report)
                                    if selectedReport?.id == report.id { selectedReport = nil }
                                }
                            }
                    }
                    .listStyle(.inset)
                }
            }
            .frame(minWidth: 280, maxWidth: 350)

            // 报告详情
            if let report = selectedReport {
                reportDetailView(report)
            } else {
                VStack {
                    Image(systemName: "chart.bar.doc.horizontal")
                        .font(.system(size: 48))
                        .foregroundColor(.secondary)
                    Text("选择报告查看详情")
                        .foregroundColor(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
    }

    // MARK: - 报告详情

    @ViewBuilder
    private func reportDetailView(_ report: TestReport) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                // 概览卡片
                HStack {
                    VStack(alignment: .leading) {
                        Text(report.taskName)
                            .font(.title.bold())
                        Text("设备: \(report.deviceName)")
                            .foregroundColor(.secondary)
                        if let start = report.startTime {
                            Text("开始: \(start.formatted())")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                    }
                    Spacer()
                    ResultBadge(status: report.status)
                }
                .padding()
                .background(Color(nsColor: .controlBackgroundColor))
                .cornerRadius(10)

                // 统计卡片
                LazyVGrid(columns: [
                    GridItem(.flexible()),
                    GridItem(.flexible()),
                    GridItem(.flexible()),
                    GridItem(.flexible())
                ], spacing: 12) {
                    StatCard(title: "总循环", value: "\(report.totalLoops)", color: .blue)
                    StatCard(title: "总事件", value: "\(report.totalEvents)", color: .purple)
                    StatCard(title: "成功率", value: String(format: "%.1f%%", report.overallSuccessRate),
                             color: report.overallSuccessRate >= 95 ? .green : .orange)
                    StatCard(title: "耗时", value: report.formattedDuration, color: .gray)
                }

                // 失败事件列表
                if !report.failedEvents.isEmpty {
                    GroupBox {
                        VStack(alignment: .leading, spacing: 8) {
                            Label("失败事件 (\(report.failedEvents.count))", systemImage: "xmark.circle.fill")
                                .foregroundColor(.red)
                                .font(.headline)

                            ForEach(report.failedEvents) { event in
                                HStack {
                                    Text(event.eventName)
                                        .fontWeight(.medium)
                                    Text(event.remark)
                                        .foregroundColor(.secondary)
                                    Spacer()
                                    if let err = event.errorMessage {
                                        Text(err)
                                            .font(.caption)
                                            .foregroundColor(.red)
                                    }
                                }
                                .padding(.vertical, 2)
                            }
                        }
                    }
                }

                // 循环详情
                GroupBox("循环详情") {
                    ForEach(report.loops) { loop in
                        DisclosureGroup(
                            isExpanded: Binding(
                                get: { expandedLoops.contains(loop.id) },
                                set: { if $0 { expandedLoops.insert(loop.id) } else { expandedLoops.remove(loop.id) } }
                            )
                        ) {
                            VStack(spacing: 4) {
                                ForEach(loop.events) { event in
                                    HStack {
                                        Image(systemName: event.status == .success ? "checkmark.circle.fill" : "xmark.circle.fill")
                                            .foregroundColor(event.status == .success ? .green : .red)
                                            .frame(width: 16)
                                        Text(event.eventName)
                                            .frame(width: 100, alignment: .leading)
                                        Text(event.remark)
                                            .foregroundColor(.secondary)
                                        if let strategy = event.strategy {
                                            Text(strategy)
                                                .font(.caption2)
                                                .foregroundColor(.blue)
                                                .lineLimit(1)
                                        }
                                        if let path = event.screenshotPath {
                                            Button {
                                                NSWorkspace.shared.open(URL(fileURLWithPath: path))
                                            } label: {
                                                Image(systemName: "photo")
                                            }
                                            .buttonStyle(.borderless)
                                            .help("打开截图: \(path)")
                                        }
                                        Spacer()
                                        if let dur = event.duration {
                                            Text(String(format: "%.2fs", dur))
                                                .font(.caption.monospacedDigit())
                                                .foregroundColor(.secondary)
                                        }
                                    }
                                    .font(.callout)
                                    .padding(.vertical, 1)
                                }
                            }
                        } label: {
                            HStack {
                                Text("循环 #\(loop.loopIndex)")
                                    .fontWeight(.medium)
                                Spacer()
                                Text("\(loop.successEvents)/\(loop.totalEvents)")
                                    .font(.caption)
                                ResultBadge(status: loop.status)
                            }
                        }
                        Divider()
                    }
                }

                // 导出按钮
                HStack {
                    Spacer()
                    Button("导出 HTML") { exportHTML(report) }
                    Button("导出 JSON") { exportJSON(report) }
                }
            }
            .padding()
        }
    }

    // MARK: - 导出

    private func exportHTML(_ report: TestReport) {
        let html = reportGenerator.exportToHTML(report)
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.html]
        panel.nameFieldStringValue = "report_\(report.taskName).html"
        if panel.runModal() == .OK, let url = panel.url {
            try? html.write(to: url, atomically: true, encoding: .utf8)
        }
    }

    private func exportJSON(_ report: TestReport) {
        guard let json = reportGenerator.exportToJSON(report) else { return }
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.json]
        panel.nameFieldStringValue = "report_\(report.taskName).json"
        if panel.runModal() == .OK, let url = panel.url {
            try? json.write(to: url, atomically: true, encoding: .utf8)
        }
    }
}

// MARK: - 辅助视图

struct ReportListRow: View {
    let report: TestReport

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(report.taskName)
                    .fontWeight(.medium)
                Spacer()
                ResultBadge(status: report.status)
            }
            HStack(spacing: 8) {
                Text(report.deviceName)
                Text(report.formattedDuration)
                Text(String(format: "%.0f%%", report.overallSuccessRate))
            }
            .font(.caption)
            .foregroundColor(.secondary)
            if let start = report.startTime {
                Text(start.formatted(date: .abbreviated, time: .shortened))
                    .font(.caption2)
                    .foregroundColor(.secondary)
            }
        }
        .padding(.vertical, 2)
    }
}

struct ResultBadge: View {
    let status: EventStatus

    var body: some View {
        Text(status == .success ? "通过" : status == .failed ? "失败" : "进行中")
            .font(.caption)
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .background(backgroundColor)
            .foregroundColor(.white)
            .clipShape(Capsule())
    }

    private var backgroundColor: Color {
        switch status {
        case .success: return .green
        case .failed: return .red
        case .running: return .orange
        default: return .gray
        }
    }
}

struct StatCard: View {
    let title: String
    let value: String
    let color: Color

    var body: some View {
        VStack(spacing: 4) {
            Text(value)
                .font(.title2.bold())
                .foregroundColor(color)
            Text(title)
                .font(.caption)
                .foregroundColor(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding()
        .background(color.opacity(0.1))
        .cornerRadius(8)
    }
}
