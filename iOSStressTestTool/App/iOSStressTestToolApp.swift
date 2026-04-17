import SwiftUI

@main
struct iOSStressTestToolApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate

    var body: some Scene {
        WindowGroup {
            MainView()
        }
        .windowStyle(.titleBar)
        .defaultSize(width: 1200, height: 800)
        .commands {
            // 文件菜单
            CommandGroup(after: .newItem) {
                Button("导入任务...") { importTasks() }
                    .keyboardShortcut("i", modifiers: [.command])
                Button("导出任务...") { exportTasks() }
                    .keyboardShortcut("e", modifiers: [.command])
            }

            // 设备菜单
            CommandMenu("设备") {
                Button("刷新设备列表") {
                    Task { await DeviceService.shared.refreshDevices() }
                }
                .keyboardShortcut("r", modifiers: [.command, .shift])

                Divider()

                Button("启动 Simulator") {
                    ProcessRunner.shared.run("/usr/bin/open", arguments: ["-a", "Simulator"])
                }
            }

            // 执行菜单
            CommandMenu("执行") {
                Button("停止执行") {
                    EventExecutor.shared.stop()
                }
                .keyboardShortcut(".", modifiers: .command)
            }
        }

        Settings {
            SettingsView()
                .frame(width: 700, height: 600)
        }
    }

    private func importTasks() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.json]
        panel.allowsMultipleSelection = false
        if panel.runModal() == .OK, let url = panel.url {
            TaskViewModel().importTasks(from: url)
        }
    }

    private func exportTasks() {
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.json]
        panel.nameFieldStringValue = "tasks_export.json"
        if panel.runModal() == .OK, let url = panel.url {
            TaskViewModel().exportTasks(to: url)
        }
    }
}
