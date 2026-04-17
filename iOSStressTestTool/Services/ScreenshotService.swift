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

    private struct CachedScreenshot {
        let image: NSImage
        let timestamp: Date
    }

    private init() {}

    // MARK: - 截图目录

    private var screenshotDirectory: URL {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let dir = appSupport.appendingPathComponent("iOSStressTestTool/screenshots")
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
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

    /// 真机截图 (通过 idevicescreenshot 或 idb)
    private func capturePhysicalDeviceScreenshot(udid: String) async -> NSImage? {
        let tempPath = NSTemporaryDirectory() + "device_screenshot_\(udid).png"

        // 优先尝试 idb
        var result = await runner.runAsync("/usr/local/bin/idb",
            arguments: ["screenshot", "--udid", udid, tempPath])

        // 备选: libimobiledevice
        if !result.isSuccess {
            result = await runner.runAsync("/usr/local/bin/idevicescreenshot",
                arguments: ["-u", udid, tempPath])
        }

        guard result.isSuccess else {
            logger.error("真机截图失败: \(result.stderr)")
            return nil
        }

        defer { try? FileManager.default.removeItem(atPath: tempPath) }
        return NSImage(contentsOfFile: tempPath)
    }

    // MARK: - 截图保存

    /// 保存截图到指定路径
    func saveScreenshot(_ image: NSImage, name: String, subfolder: String? = nil) -> String? {
        var dir = screenshotDirectory
        if let subfolder = subfolder {
            dir = dir.appendingPathComponent(subfolder)
            try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        }

        let timestamp = DateFormatter.fileNameFormatter.string(from: Date())
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
