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
    /// 仓库根目录（…/<repo>/iOSStressTestTool/Utils/HostEnvironment.swift）
    nonisolated static let repositoryRoot: String? = {
        let thisFile = URL(fileURLWithPath: #filePath)
        let root = thisFile
            .deletingLastPathComponent()   // Utils
            .deletingLastPathComponent()   // iOSStressTestTool
            .deletingLastPathComponent()   // <repo>
        var isDir: ObjCBool = false
        guard FileManager.default.fileExists(atPath: root.path, isDirectory: &isDir),
              isDir.boolValue else { return nil }
        return root.path
    }()

    static var applicationSupportDirectory: String {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        return base.appendingPathComponent("iOSStressTestTool", isDirectory: true).path
    }

    static var logsDirectory: String {
        applicationSupportDirectory + "/logs"
    }

    static var appiumLogPath: String {
        logsDirectory + "/appium-server.log"
    }

    /// Appium 的 driver 安装目录。优先用仓库内置副本，便于本机开发。
    static var appiumHome: String {
        if let root = repositoryRoot {
            let local = root + "/.tools/appium-home"
            if FileManager.default.fileExists(atPath: local) { return local }
        }
        return applicationSupportDirectory + "/appium-home"
    }

    /// WDA 构建缓存目录。优先复用仓库内的缓存，冷启动能省 8–9 分钟。
    static var derivedDataPath: String {
        if let root = repositoryRoot {
            return root + "/.tools/DerivedData"
        }
        return applicationSupportDirectory + "/WDA-DerivedData"
    }

    /// Appium 可执行文件候选路径。
    static func appiumExecutable() -> String? {
        var candidates: [String] = []

        if let override = ProcessInfo.processInfo.environment["APPIUM_BINARY"], !override.isEmpty {
            candidates.append(override)
        }
        if let root = repositoryRoot {
            candidates.append(root + "/.tools/appium/node_modules/.bin/appium")
        }
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
