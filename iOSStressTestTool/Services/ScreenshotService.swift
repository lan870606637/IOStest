import Foundation
import AppKit
import CoreGraphics

// MARK: - 截图服务
/// 管理设备截图的获取、缓存和保存
@MainActor
final class ScreenshotService: ObservableObject {
    static let shared = ScreenshotService()

    @Published var latestScreenshot: NSImage?
    @Published var isCapturing = false

    private let runner = ProcessRunner.shared
    private let logger = Logger.shared
    private var cache: [String: CachedScreenshot] = [:]
    private let cacheQueue = DispatchQueue(label: "com.stresstesttool.screenshot.cache")

    private static let screenshotTimestampFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "yyyyMMdd_HHmmss_SSS"
        return f
    }()

    private struct CachedScreenshot {
        let image: NSImage
        let timestamp: Date
    }

    private init() {}

    // MARK: - 截图目录

    private var screenshotDirectory: URL {
        let fm = FileManager.default
        let configured = AppConfig.shared.screenshotSaveDir
            .trimmingCharacters(in: .whitespacesAndNewlines)

        let dir: URL
        if configured.hasPrefix("/") {
            dir = URL(fileURLWithPath: configured, isDirectory: true)
        } else {
            let appSupport = fm.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
            let sub = configured.isEmpty ? "screenshots" : configured
            dir = appSupport.appendingPathComponent("iOSStressTestTool/\(sub)", isDirectory: true)
        }

        try? fm.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    /// 当前截图保存目录（设置页/报告页展示、打开用）
    var currentDirectoryPath: String {
        screenshotDirectory.path
    }

    // MARK: - 截图获取

    /// 获取设备截图
    func captureScreenshot(deviceUDID: String, deviceType: DeviceType) async -> NSImage? {
        // 检查缓存
        if let cached = getCachedScreenshot(for: deviceUDID) {
            return cached
        }

        isCapturing = true
        defer { Task { @MainActor in isCapturing = false } }

        let image: NSImage?
        switch deviceType {
        case .simulator:
            image = await captureSimulatorScreenshot(udid: deviceUDID)
        case .physical:
            image = await capturePhysicalDeviceScreenshot(udid: deviceUDID)
        }

        if let img = image {
            setCachedScreenshot(img, for: deviceUDID)
            await MainActor.run { self.latestScreenshot = img }
        }

        return image
    }

    /// 模拟器截图 (通过 simctl io screenshot)
    private func captureSimulatorScreenshot(udid: String) async -> NSImage? {
        let tempPath = NSTemporaryDirectory() + "sim_screenshot_\(udid).png"
        let result = await runner.simctlAsync(["io", udid, "screenshot", "--type=png", tempPath])

        guard result.isSuccess else {
            logger.error("模拟器截图失败: \(result.stderr)")
            return nil
        }

        defer { try? FileManager.default.removeItem(atPath: tempPath) }
        return NSImage(contentsOfFile: tempPath)
    }

    /// 真机截图
    /// iOS 17+ 已移除旧 screenshotr 服务，优先使用 go-ios（DVT 截图通道 + userspace 隧道），
    /// 其次 idb / idevicescreenshot。截图属免签名能力，不需要 WDA。
    private func capturePhysicalDeviceScreenshot(udid: String) async -> NSImage? {
        let tempPath = NSTemporaryDirectory() + "device_screenshot_\(udid).png"

        // 方法1: go-ios（隧道 + 截图逻辑统一封装在 GoIOSClient 中）
        if await GoIOSClient.shared.screenshot(udid: udid, outputPath: tempPath) {
            if let image = NSImage(contentsOfFile: tempPath) {
                try? FileManager.default.removeItem(atPath: tempPath)
                return image
            }
            logger.warning("go-ios 截图成功但图像无法解码: \(tempPath)")
        }

        // 方法2: idb / idevicescreenshot
        let candidateDirs = ["/opt/homebrew/bin", "/usr/local/bin"]

        // 优先尝试 idb
        var result = ProcessResult(exitCode: -1, stdout: "", stderr: "idb 未找到")
        if let idbPath = findTool(named: "idb", in: candidateDirs) {
            result = await runner.runAsync(idbPath, arguments: ["screenshot", "--udid", udid, tempPath])
        }

        // 备选: libimobiledevice 的 idevicescreenshot
        if !result.isSuccess {
            if let idevicePath = findTool(named: "idevicescreenshot", in: candidateDirs) {
                result = await runner.runAsync(idevicePath, arguments: ["-u", udid, tempPath])
            } else {
                result = ProcessResult(exitCode: -1, stdout: "", stderr: "idevicescreenshot 未找到")
            }
        }

        guard result.isSuccess else {
            logger.error("真机截图失败: \(result.stderr)。可安装工具: brew install libimobiledevice (截图) 或 brew install go-ios (推荐，支持 iOS 17+)")
            return nil
        }

        defer { try? FileManager.default.removeItem(atPath: tempPath) }
        return NSImage(contentsOfFile: tempPath)
    }

    /// 在候选目录中查找可执行工具
    private func findTool(named name: String, in dirs: [String]) -> String? {
        for dir in dirs {
            let path = dir + "/" + name
            if FileManager.default.isExecutableFile(atPath: path) {
                return path
            }
        }
        return nil
    }

    // MARK: - 截图保存

    /// 保存截图到指定路径
    func saveScreenshot(_ image: NSImage, name: String, subfolder: String? = nil) -> String? {
        var dir = screenshotDirectory
        if let subfolder = subfolder {
            dir = dir.appendingPathComponent(subfolder)
            try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        }

        let timestamp = Self.screenshotTimestampFormatter.string(from: Date())
        let fileName = "\(name)_\(timestamp).png"
        let filePath = dir.appendingPathComponent(fileName)

        guard let tiffData = image.tiffRepresentation,
              let bitmap = NSBitmapImageRep(data: tiffData),
              let pngData = bitmap.representation(using: .png, properties: [:]) else {
            logger.error("截图数据转换失败")
            return nil
        }

        do {
            try pngData.write(to: filePath)
            logger.debug("截图已保存: \(filePath.path)")
            return filePath.path
        } catch {
            logger.error("保存截图失败: \(error)")
            return nil
        }
    }

    /// 保存截图并返回 base64
    func screenshotToBase64(_ image: NSImage) -> String? {
        guard let tiffData = image.tiffRepresentation,
              let bitmap = NSBitmapImageRep(data: tiffData),
              let pngData = bitmap.representation(using: .png, properties: [:]) else { return nil }
        return pngData.base64EncodedString()
    }

    // MARK: - 缓存管理

    private func getCachedScreenshot(for udid: String) -> NSImage? {
        cacheQueue.sync {
            guard let cached = cache[udid] else { return nil }
            let expiry = AppConfig.shared.screenshotCacheExpiry
            if Date().timeIntervalSince(cached.timestamp) < expiry {
                return cached.image
            }
            cache.removeValue(forKey: udid)
            return nil
        }
    }

    private func setCachedScreenshot(_ image: NSImage, for udid: String) {
        cacheQueue.sync {
            cache[udid] = CachedScreenshot(image: image, timestamp: Date())
        }
    }

    func clearCache() {
        cacheQueue.sync { cache.removeAll() }
    }

    func invalidateCache(for udid: String) {
        cacheQueue.sync { cache.removeValue(forKey: udid) }
    }

    // MARK: - 临时截图管理

    func cleanTempScreenshots() {
        let tempDir = NSTemporaryDirectory()
        let fm = FileManager.default
        guard let files = try? fm.contentsOfDirectory(atPath: tempDir) else { return }
        for file in files where file.contains("screenshot") && file.hasSuffix(".png") {
            try? fm.removeItem(atPath: tempDir + file)
        }
    }
}
