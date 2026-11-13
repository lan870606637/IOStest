import Foundation

// MARK: - 主机环境自检
/// 检查 iOS 自动化所需的系统配置。
///
/// 这些检查来自 2026-10-29 的 spike：`Developer mode` 关闭时，
/// `xcodebuild test` 会卡在 `Running tests...`，testmanagerd 握手永远等不到 test host；
/// `xcode-select` 指向 CommandLineTools 时，部分子进程会找不到 `simctl`。
struct HostEnvironmentCheck: Identifiable {
    enum Status {
        case ok
        case warning
        case failed

        var symbol: String {
            switch self {
            case .ok: return "checkmark.circle.fill"
            case .warning: return "exclamationmark.triangle.fill"
            case .failed: return "xmark.circle.fill"
            }
        }

        var label: String {
            switch self {
            case .ok: return "正常"
            case .warning: return "警告"
            case .failed: return "不可用"
            }
        }
    }

    let id = UUID()
    let name: String
    let status: Status
    let detail: String
    let fix: String?
}

enum HostEnvironment {
    static var applicationSupportDirectory: String {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        return base.appendingPathComponent("iOSStressTestTool", isDirectory: true).path
    }

    /// App 自己的运行时目录（Appium、driver、WDA 缓存、go-ios）。
    /// 放在 Application Support，避免 App 访问桌面触发 macOS TCC 弹窗。
    static var runtimeDirectory: String {
        applicationSupportDirectory + "/runtime"
    }

    static var logsDirectory: String {
        applicationSupportDirectory + "/logs"
    }

    static var appiumLogPath: String {
        logsDirectory + "/appium-server.log"
    }

    /// Appium 的 driver 安装目录（Application Support 内，避免桌面权限）。
    static var appiumHome: String {
        runtimeDirectory + "/appium-home"
    }

    /// WDA 构建缓存目录。
    static var derivedDataPath: String {
        runtimeDirectory + "/WDA-DerivedData"
    }

    /// Appium 可执行文件候选路径。
    static func appiumExecutable() -> String? {
        var candidates: [String] = []

        if let override = ProcessInfo.processInfo.environment["APPIUM_BINARY"], !override.isEmpty {
            candidates.append(override)
        }
        candidates.append(runtimeDirectory + "/appium/node_modules/.bin/appium")
        candidates.append("/opt/homebrew/bin/appium")
        candidates.append("/usr/local/bin/appium")

        for path in candidates where FileManager.default.isExecutableFile(atPath: path) {
            return path
        }

        let which = ProcessRunner.shared.run("/usr/bin/which", arguments: ["appium"])
        if which.isSuccess {
            let path = which.output
            if !path.isEmpty, FileManager.default.isExecutableFile(atPath: path) {
                return path
            }
        }
        return nil
    }

    static func developerModeEnabled() -> Bool {
        let result = ProcessRunner.shared.run("/usr/sbin/DevToolsSecurity", arguments: ["-status"])
        return result.stdout.lowercased().contains("enabled")
    }

    static func developerDirectory() -> String {
        ProcessRunner.shared.run("/usr/bin/xcode-select", arguments: ["-p"]).output
    }

    /// 只有指向 Xcode 的开发者目录才能可靠地跑 simctl / xcodebuild test。
    static func developerDirectoryIsXcode() -> Bool {
        let dir = developerDirectory()
        return dir.contains("Xcode.app") && FileManager.default.fileExists(atPath: dir)
    }

    static func xcodeInstalled() -> Bool {
        FileManager.default.fileExists(atPath: "/Applications/Xcode.app")
    }

    static func xcuitestDriverInstalled() -> Bool {
        let package = appiumHome + "/node_modules/appium-xcuitest-driver/package.json"
        return FileManager.default.fileExists(atPath: package)
    }

    /// 查找 Node.js。Appium 的 CLI 是 `#!/usr/bin/env node`，PATH 里没有 node 就会
    /// 报 `env: node: No such file or directory`。
    static func nodeExecutable() -> String? {
        let fm = FileManager.default
        var candidates: [String] = []

        if let override = ProcessInfo.processInfo.environment["NODE_BINARY"], !override.isEmpty {
            candidates.append(override)
        }
        candidates.append("/opt/homebrew/bin/node")
        candidates.append("/usr/local/bin/node")

        let home = NSHomeDirectory()
        let versionRoots = [
            home + "/.workbuddy/binaries/node/versions",
            home + "/.nvm/versions/node",
            home + "/.fnm/node-versions",
        ]
        for root in versionRoots {
            guard let versions = try? fm.contentsOfDirectory(atPath: root) else { continue }
            for version in versions {
                candidates.append(root + "/" + version + "/bin/node")
                candidates.append(root + "/" + version + "/installation/bin/node")
            }
        }
        candidates.append(home + "/.volta/bin/node")

        for path in candidates where fm.isExecutableFile(atPath: path) {
            return path
        }

        // 兜底：登录 shell 的 PATH（能覆盖 nvm/volta 等动态配置）
        let result = ProcessRunner.shared.run("/bin/zsh",
                                              arguments: ["-lc", "command -v node"],
                                              timeout: 5)
        let path = result.output
        if result.isSuccess, !path.isEmpty, fm.isExecutableFile(atPath: path) {
            return path
        }
        return nil
    }

    static var nodeDirectory: String? {
        guard let node = nodeExecutable() else { return nil }
        return URL(fileURLWithPath: node).deletingLastPathComponent().path
    }

    static func prepareRuntimeDirectories() throws {
        let fm = FileManager.default
        for dir in [appiumHome, derivedDataPath, logsDirectory] {
            try fm.createDirectory(atPath: dir, withIntermediateDirectories: true)
        }
    }

    static func checks() -> [HostEnvironmentCheck] {
        var result: [HostEnvironmentCheck] = []

        // 1. Developer mode（XCTest 必需）
        let devMode = developerModeEnabled()
        result.append(HostEnvironmentCheck(
            name: "Developer mode",
            status: devMode ? .ok : .failed,
            detail: devMode ? "已启用" : "已关闭，xcodebuild test 会卡在 Running tests...",
            fix: devMode ? nil : "sudo /usr/sbin/DevToolsSecurity -enable"
        ))

        // 2. xcode-select
        let devDir = developerDirectory()
        let dirOK = developerDirectoryIsXcode()
        result.append(HostEnvironmentCheck(
            name: "xcode-select",
            status: dirOK ? .ok : .failed,
            detail: devDir.isEmpty ? "未设置" : devDir,
            fix: dirOK ? nil : "sudo xcode-select -s /Applications/Xcode.app/Contents/Developer"
        ))

        // 3. Xcode
        result.append(HostEnvironmentCheck(
            name: "Xcode",
            status: xcodeInstalled() ? .ok : .failed,
            detail: xcodeInstalled() ? "/Applications/Xcode.app" : "未安装 Xcode",
            fix: xcodeInstalled() ? nil : "从 App Store 安装 Xcode"
        ))

        // 4. Appium
        if let appium = appiumExecutable() {
            result.append(HostEnvironmentCheck(
                name: "Appium",
                status: .ok,
                detail: appium,
                fix: nil
            ))
        } else {
            result.append(HostEnvironmentCheck(
                name: "Appium",
                status: .failed,
                detail: "未找到 appium 可执行文件",
                fix: "npm i -g appium@3 或设置 APPIUM_BINARY"
            ))
        }

        // 5. XCUITest driver
        let driverOK = xcuitestDriverInstalled()
        result.append(HostEnvironmentCheck(
            name: "XCUITest driver",
            status: driverOK ? .ok : .failed,
            detail: driverOK ? appiumHome : "未在 \(appiumHome) 找到 appium-xcuitest-driver",
            fix: driverOK ? nil : "APPIUM_HOME=\(appiumHome) appium driver install xcuitest"
        ))

        // 6. Node.js（Appium 启动必需）
        let node = nodeExecutable()
        result.append(HostEnvironmentCheck(
            name: "Node.js (Appium)",
            status: node != nil ? .ok : .failed,
            detail: node ?? "未找到 node",
            fix: node != nil ? nil : "安装 Node.js 20+，或设置 NODE_BINARY"
        ))

        // 6. 代码签名证书（真机必需）
        let identitiesOutput = ProcessRunner.shared.run(
            "/usr/bin/security",
            arguments: ["find-identity", "-v", "-p", "codesigning"]
        ).stdout
        let identityLines = identitiesOutput
            .components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { $0.contains("Apple Development") || $0.contains("Apple Distribution") }
        result.append(HostEnvironmentCheck(
            name: "签名证书",
            status: identityLines.isEmpty ? .failed : .ok,
            detail: identityLines.first ?? "未找到 Apple Development 证书",
            fix: identityLines.isEmpty
                ? "Xcode → Settings → Accounts → Manage Certificates → + → Apple Development"
                : nil
        ))

        return result
    }
}
