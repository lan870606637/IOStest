import Foundation
import os

// MARK: - 日志级别
enum LogLevel: Int, Comparable {
    case debug = 0
    case info = 1
    case warning = 2
    case error = 3
    case critical = 4

    var prefix: String {
        switch self {
        case .debug: return "🔍 DEBUG"
        case .info: return "ℹ️ INFO"
        case .warning: return "⚠️ WARNING"
        case .error: return "❌ ERROR"
        case .critical: return "🔥 CRITICAL"
        }
    }

    static func < (lhs: LogLevel, rhs: LogLevel) -> Bool {
        lhs.rawValue < rhs.rawValue
    }
}

// MARK: - 日志管理器
final class Logger {
    static let shared = Logger()

    private let queue = DispatchQueue(label: "com.stresstesttool.logger", qos: .utility)
    private var fileHandle: FileHandle?
    private var currentLogPath: URL?
    private let dateFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd HH:mm:ss.SSS"
        return f
    }()

    var minLevel: LogLevel = .debug
    var onLog: ((LogLevel, String) -> Void)?

    private init() {
        setupLogFile()
    }

    deinit {
        fileHandle?.closeFile()
    }

    // MARK: - 日志文件管理

    private var logDirectory: URL {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let dir = appSupport.appendingPathComponent("iOSStressTestTool/logs")
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    private func setupLogFile() {
        let fileName = "app_\(DateFormatter.fileNameFormatter.string(from: Date())).log"
        let path = logDirectory.appendingPathComponent(fileName)
        FileManager.default.createFile(atPath: path.path, contents: nil)
        fileHandle = try? FileHandle(forWritingTo: path)
        fileHandle?.seekToEndOfFile()
        currentLogPath = path
    }

    // MARK: - 日志方法

    func debug(_ message: String, file: String = #file, function: String = #function, line: Int = #line) {
        log(.debug, message, file: file, function: function, line: line)
    }

    func info(_ message: String, file: String = #file, function: String = #function, line: Int = #line) {
        log(.info, message, file: file, function: function, line: line)
    }

    func warning(_ message: String, file: String = #file, function: String = #function, line: Int = #line) {
        log(.warning, message, file: file, function: function, line: line)
    }

    func error(_ message: String, file: String = #file, function: String = #function, line: Int = #line) {
        log(.error, message, file: file, function: function, line: line)
    }

    func critical(_ message: String, file: String = #file, function: String = #function, line: Int = #line) {
        log(.critical, message, file: file, function: function, line: line)
    }

    private func log(_ level: LogLevel, _ message: String, file: String, function: String, line: Int) {
        guard level >= minLevel else { return }

        let timestamp = dateFormatter.string(from: Date())
        let fileName = (file as NSString).lastPathComponent
        let logMessage = "[\(timestamp)] \(level.prefix) [\(fileName):\(line)] \(function) - \(message)"

        queue.async { [weak self] in
            // 写入文件
            if let data = (logMessage + "\n").data(using: .utf8) {
                self?.fileHandle?.write(data)
            }

            // 控制台输出
            #if DEBUG
            print(logMessage)
            #endif

            // 回调通知
            DispatchQueue.main.async {
                self?.onLog?(level, logMessage)
            }
        }
    }

    // MARK: - 日志文件操作

    func getLogFiles() -> [URL] {
        let files = (try? FileManager.default.contentsOfDirectory(at: logDirectory, includingPropertiesForKeys: [.creationDateKey])) ?? []
        return files.filter { $0.pathExtension == "log" }.sorted {
            let d1 = (try? $0.resourceValues(forKeys: [.creationDateKey]).creationDate) ?? Date.distantPast
            let d2 = (try? $1.resourceValues(forKeys: [.creationDateKey]).creationDate) ?? Date.distantPast
            return d1 > d2
        }
    }

    func clearOldLogs(keepDays: Int = 7) {
        let cutoff = Calendar.current.date(byAdding: .day, value: -keepDays, to: Date()) ?? Date()
        for file in getLogFiles() {
            if let date = try? file.resourceValues(forKeys: [.creationDateKey]).creationDate,
               date < cutoff {
                try? FileManager.default.removeItem(at: file)
            }
        }
    }
}

// MARK: - DateFormatter 扩展
extension DateFormatter {
    static let fileNameFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "yyyyMMdd_HHmmss"
        return f
    }()
}
