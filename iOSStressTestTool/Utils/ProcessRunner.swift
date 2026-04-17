import Foundation

// MARK: - 命令执行结果
struct ProcessResult {
    let exitCode: Int32
    let stdout: String
    let stderr: String

    var isSuccess: Bool { exitCode == 0 }

    var output: String {
        stdout.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

// MARK: - 进程运行器
/// 封装 macOS 命令行工具调用 (xcrun, simctl, idb 等)
final class ProcessRunner {
    static let shared = ProcessRunner()
    private let logger = Logger.shared

    private init() {}

    // MARK: - 同步执行

    @discardableResult
    func run(_ executable: String, arguments: [String] = [], timeout: TimeInterval = 30) -> ProcessResult {
        let process = Process()
        let stdoutPipe = Pipe()
        let stderrPipe = Pipe()

        process.executableURL = URL(fileURLWithPath: executable)
        process.arguments = arguments
        process.standardOutput = stdoutPipe
        process.standardError = stderrPipe

        logger.debug("执行命令: \(executable) \(arguments.joined(separator: " "))")

        do {
            try process.run()
        } catch {
            logger.error("启动进程失败: \(error.localizedDescription)")
            return ProcessResult(exitCode: -1, stdout: "", stderr: error.localizedDescription)
        }

        // 超时处理
        let timer = DispatchSource.makeTimerSource()
        timer.schedule(deadline: .now() + timeout)
        timer.setEventHandler {
            if process.isRunning {
                process.terminate()
            }
        }
        timer.resume()

        // 先异步读取管道数据，避免管道缓冲区满导致死锁
        var stdoutData = Data()
        var stderrData = Data()
        let readGroup = DispatchGroup()

        readGroup.enter()
        DispatchQueue.global(qos: .userInitiated).async {
            stdoutData = stdoutPipe.fileHandleForReading.readDataToEndOfFile()
            readGroup.leave()
        }
        readGroup.enter()
        DispatchQueue.global(qos: .userInitiated).async {
            stderrData = stderrPipe.fileHandleForReading.readDataToEndOfFile()
            readGroup.leave()
        }

        process.waitUntilExit()
        readGroup.wait()
        timer.cancel()

        let result = ProcessResult(
            exitCode: process.terminationStatus,
            stdout: String(data: stdoutData, encoding: .utf8) ?? "",
            stderr: String(data: stderrData, encoding: .utf8) ?? ""
        )

        if !result.isSuccess {
            logger.warning("命令退出码: \(result.exitCode), stderr: \(result.stderr)")
        }

        return result
    }

    // MARK: - 异步执行

    func runAsync(_ executable: String, arguments: [String] = [], timeout: TimeInterval = 30) async -> ProcessResult {
        await withCheckedContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async { [weak self] in
                guard let self else {
                    continuation.resume(returning: ProcessResult(exitCode: -1, stdout: "", stderr: "Runner deallocated"))
                    return
                }
                let result = self.run(executable, arguments: arguments, timeout: timeout)
                continuation.resume(returning: result)
            }
        }
    }

    // MARK: - 便捷方法

    /// 执行 xcrun 命令
    @discardableResult
    func xcrun(_ arguments: [String], timeout: TimeInterval = 30) -> ProcessResult {
        run("/usr/bin/xcrun", arguments: arguments, timeout: timeout)
    }

    /// 执行 xcrun simctl 命令
    @discardableResult
    func simctl(_ arguments: [String], timeout: TimeInterval = 30) -> ProcessResult {
        xcrun(["simctl"] + arguments, timeout: timeout)
    }

    /// 异步执行 xcrun simctl 命令
    func simctlAsync(_ arguments: [String], timeout: TimeInterval = 30) async -> ProcessResult {
        await runAsync("/usr/bin/xcrun", arguments: ["simctl"] + arguments, timeout: timeout)
    }

    /// 执行 xcodebuild 命令
    @discardableResult
    func xcodebuild(_ arguments: [String], timeout: TimeInterval = 600) -> ProcessResult {
        run("/usr/bin/xcodebuild", arguments: arguments, timeout: timeout)
    }

    /// 异步执行 xcodebuild 命令
    func xcodebuildAsync(_ arguments: [String], timeout: TimeInterval = 600) async -> ProcessResult {
        await runAsync("/usr/bin/xcodebuild", arguments: arguments, timeout: timeout)
    }

    /// 执行 idb 命令 (Facebook's iOS Development Bridge)
    @discardableResult
    func idb(_ arguments: [String], timeout: TimeInterval = 30) -> ProcessResult {
        run("/usr/local/bin/idb", arguments: arguments, timeout: timeout)
    }

    /// 检查工具是否可用
    func isToolAvailable(_ toolPath: String) -> Bool {
        FileManager.default.isExecutableFile(atPath: toolPath)
    }

    /// 查找命令路径
    func which(_ command: String) -> String? {
        let result = run("/usr/bin/which", arguments: [command])
        return result.isSuccess ? result.output : nil
    }
}
