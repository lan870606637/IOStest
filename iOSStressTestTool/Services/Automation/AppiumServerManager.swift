import Foundation
import Darwin

// MARK: - Appium 服务进程管理
/// App 启动时自动拉起 Appium，退出时关闭；也可复用已经在 4723 上跑着的实例。
actor AppiumServerManager {
    static let shared = AppiumServerManager()

    enum State: Equatable {
        case stopped
        case starting
        case running
        case failed(String)

        var displayName: String {
            switch self {
            case .stopped: return "未启动"
            case .starting: return "启动中"
            case .running: return "运行中"
            case .failed(let message): return "启动失败：\(message)"
            }
        }
    }

    private(set) var state: State = .stopped
    private(set) var baseURL: URL?

    private var process: Process?
    private var logHandle: FileHandle?
    private var startTask: Task<URL, Error>?

    private static let defaultURL = URL(string: "http://127.0.0.1:4723")!
    private static let portRange = 4723...4740

    // MARK: - 生命周期

    func ensureRunning() async throws -> URL {
        if let baseURL, await Self.isServerReady(baseURL) {
            return baseURL
        }

        // 复用已经在默认端口运行的 Appium（例如开发时手动启动的）。
        if await Self.isServerReady(Self.defaultURL) {
            baseURL = Self.defaultURL
            state = .running
            return Self.defaultURL
        }

        if let startTask {
            return try await startTask.value
        }

        let task = Task<URL, Error> { try await self.start() }
        startTask = task
        do {
            let url = try await task.value
            startTask = nil
            baseURL = url
            return url
        } catch {
            startTask = nil
            throw error
        }
    }

    func stop() async {
        guard let process else {
            state = .stopped
            baseURL = nil
            return
        }

        let rootPID = process.processIdentifier
        let descendants = Self.processTree(root: rootPID)

        process.terminate()
        for child in descendants.reversed() {
            kill(child, SIGTERM)
        }
        try? await Task.sleep(nanoseconds: 1_500_000_000)

        for child in descendants where kill(child, 0) == 0 {
            kill(child, SIGKILL)
        }
        if process.isRunning {
            kill(rootPID, SIGKILL)
        }

        self.process = nil
        baseURL = nil
        state = .stopped
        try? logHandle?.close()
        logHandle = nil
    }

    func restart() async throws -> URL {
        await stop()
        return try await ensureRunning()
    }

    func stateDescription() -> String {
        state.displayName
    }

    func logPath() -> String {
        HostEnvironment.appiumLogPath
    }

    // MARK: - 启动

    private func start() async throws -> URL {
        state = .starting

        guard let binary = HostEnvironment.appiumExecutable() else {
            let message = "未找到 appium。安装：npm i -g appium@3，或设置 APPIUM_BINARY"
            state = .failed(message)
            throw AutomationError.backendUnavailable(message)
        }

        do {
            try HostEnvironment.prepareRuntimeDirectories()
        } catch {
            let message = "创建运行目录失败：\(error.localizedDescription)"
            state = .failed(message)
            throw AutomationError.backendUnavailable(message)
        }

        let port = Self.findFreePort() ?? 4723
        let url = URL(string: "http://127.0.0.1:\(port)")!

        let logURL = URL(fileURLWithPath: HostEnvironment.appiumLogPath)
        FileManager.default.createFile(atPath: logURL.path, contents: nil)
        let handle: FileHandle
        do {
            handle = try FileHandle(forWritingTo: logURL)
        } catch {
            let message = "无法写入 Appium 日志 \(logURL.path)：\(error.localizedDescription)"
            state = .failed(message)
            throw AutomationError.backendUnavailable(message)
        }

        let process = Process()
        process.executableURL = URL(fileURLWithPath: binary)
        process.arguments = [
            "--address", "127.0.0.1",
            "--port", "\(port)",
            "--log", logURL.path,
            "--log-level", "info",
        ]

        var environment = ProcessInfo.processInfo.environment
        environment["APPIUM_HOME"] = HostEnvironment.appiumHome
        if HostEnvironment.developerDirectoryIsXcode() {
            environment["DEVELOPER_DIR"] = HostEnvironment.developerDirectory()
        }
        environment["PATH"] = "/opt/homebrew/bin:/usr/local/bin:" + (environment["PATH"] ?? "/usr/bin:/bin:/usr/sbin:/sbin")
        process.environment = environment
        process.standardOutput = handle
        process.standardError = handle

        process.terminationHandler = { [weak self] terminated in
            Task { await self?.handleTermination(terminated) }
        }

        do {
            try process.run()
        } catch {
            try? handle.close()
            let message = "启动 appium 失败：\(error.localizedDescription)"
            state = .failed(message)
            throw AutomationError.backendUnavailable(message)
        }

        self.process = process
        self.logHandle = handle

        let ready = await waitForReady(url, timeout: 60)
        guard ready else {
            process.terminate()
            self.process = nil
            try? handle.close()
            self.logHandle = nil
            let message = "Appium 未在 60 秒内就绪，见日志 \(logURL.path)"
            state = .failed(message)
            throw AutomationError.backendUnavailable(message)
        }

        state = .running
        return url
    }

    private func handleTermination(_ terminated: Process) {
        guard process === terminated else { return }
        process = nil
        baseURL = nil
        if case .failed = state {
            // 保留失败原因
        } else {
            state = .stopped
        }
        try? logHandle?.close()
        logHandle = nil
    }

    // MARK: - 健康检查

    /// 递归收集子进程（xcodebuild / WDA runner），退出时一并清理，避免孤儿进程。
    private static func processTree(root: pid_t) -> [pid_t] {
        var result: [pid_t] = []
        var queue: [pid_t] = [root]

        while !queue.isEmpty {
            let current = queue.removeFirst()
            let children = ProcessRunner.shared.run("/usr/bin/pgrep", arguments: ["-P", "\(current)"])
            guard children.isSuccess else { continue }
            for line in children.stdout.split(separator: "\n") {
                guard let pid = Int32(line.trimmingCharacters(in: .whitespaces)), pid > 0 else { continue }
                result.append(pid)
                queue.append(pid)
            }
        }
        return result
    }

    private func waitForReady(_ url: URL, timeout: TimeInterval) async -> Bool {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if await Self.isServerReady(url, timeout: 2) {
                return true
            }
            try? await Task.sleep(nanoseconds: 500_000_000)
        }
        return false
    }

    static func isServerReady(_ url: URL, timeout: TimeInterval = 2) async -> Bool {
        var request = URLRequest(url: url.appendingPathComponent("status"))
        request.timeoutInterval = timeout
        guard let (data, response) = try? await URLSession.shared.data(for: request),
              let http = response as? HTTPURLResponse,
              http.statusCode == 200,
              let text = String(data: data, encoding: .utf8) else {
            return false
        }
        return text.contains("\"ready\":true")
    }

    // MARK: - 端口

    private static func findFreePort() -> Int? {
        for port in portRange where isPortFree(port) {
            return port
        }
        return nil
    }

    private static func isPortFree(_ port: Int) -> Bool {
        let descriptor = socket(AF_INET, SOCK_STREAM, 0)
        guard descriptor >= 0 else { return false }
        defer { close(descriptor) }

        var address = sockaddr_in()
        address.sin_family = sa_family_t(AF_INET)
        address.sin_port = in_port_t(UInt16(port).bigEndian)
        address.sin_addr.s_addr = inet_addr("127.0.0.1")

        let result = withUnsafePointer(to: &address) { pointer in
            pointer.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                Darwin.bind(descriptor, $0, socklen_t(MemoryLayout<sockaddr_in>.size))
            }
        }
        return result == 0
    }
}
