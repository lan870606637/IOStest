import Foundation

// MARK: - 应用配置
final class AppConfig: ObservableObject, Codable {
    static let shared = AppConfig.load()

    // 设备设置
    @Published var defaultScreenWidth: Int = 390
    @Published var defaultScreenHeight: Int = 844
    @Published var screenshotRefreshInterval: Double = 1.0
    @Published var devicePollInterval: Double = 5.0

    // 执行设置
    @Published var defaultEventDelay: Double = 1.0
    @Published var retryCount: Int = 3
    @Published var commandTimeout: Double = 30.0

    // 图像识别设置
    @Published var defaultSimilarityThreshold: Int = 80
    @Published var imageScaleFactors: [Double] = [0.5, 0.75, 1.0, 1.25, 1.5]

    // 截图设置
    @Published var screenshotCacheExpiry: Double = 30.0
    @Published var screenshotSaveDir: String = "screenshots"

    // 日志设置
    @Published var logLevel: String = "DEBUG"
    @Published var maxLogFileSize: Int = 10_000_000

    // 录制设置
    @Published var recordingAutoDelay: Bool = true
    @Published var recordingMinDelay: Double = 0.3
    @Published var recordingMaxDelay: Double = 5.0

    // Xcode 设置
    @Published var xcodeProjectPath: String = ""
    @Published var testTargetName: String = "iOSStressTestUITests"
    @Published var derivedDataPath: String = ""

    enum CodingKeys: String, CodingKey {
        case defaultScreenWidth, defaultScreenHeight
        case screenshotRefreshInterval, devicePollInterval
        case defaultEventDelay, retryCount, commandTimeout
        case defaultSimilarityThreshold, imageScaleFactors
        case screenshotCacheExpiry, screenshotSaveDir
        case logLevel, maxLogFileSize
        case recordingAutoDelay, recordingMinDelay, recordingMaxDelay
        case xcodeProjectPath, testTargetName, derivedDataPath
    }

    init() {}

    required init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        defaultScreenWidth = try container.decodeIfPresent(Int.self, forKey: .defaultScreenWidth) ?? 390
        defaultScreenHeight = try container.decodeIfPresent(Int.self, forKey: .defaultScreenHeight) ?? 844
        screenshotRefreshInterval = try container.decodeIfPresent(Double.self, forKey: .screenshotRefreshInterval) ?? 1.0
        devicePollInterval = try container.decodeIfPresent(Double.self, forKey: .devicePollInterval) ?? 5.0
        defaultEventDelay = try container.decodeIfPresent(Double.self, forKey: .defaultEventDelay) ?? 1.0
        retryCount = try container.decodeIfPresent(Int.self, forKey: .retryCount) ?? 3
        commandTimeout = try container.decodeIfPresent(Double.self, forKey: .commandTimeout) ?? 30.0
        defaultSimilarityThreshold = try container.decodeIfPresent(Int.self, forKey: .defaultSimilarityThreshold) ?? 80
        imageScaleFactors = try container.decodeIfPresent([Double].self, forKey: .imageScaleFactors) ?? [0.5, 0.75, 1.0, 1.25, 1.5]
        screenshotCacheExpiry = try container.decodeIfPresent(Double.self, forKey: .screenshotCacheExpiry) ?? 30.0
        screenshotSaveDir = try container.decodeIfPresent(String.self, forKey: .screenshotSaveDir) ?? "screenshots"
        logLevel = try container.decodeIfPresent(String.self, forKey: .logLevel) ?? "DEBUG"
        maxLogFileSize = try container.decodeIfPresent(Int.self, forKey: .maxLogFileSize) ?? 10_000_000
        recordingAutoDelay = try container.decodeIfPresent(Bool.self, forKey: .recordingAutoDelay) ?? true
        recordingMinDelay = try container.decodeIfPresent(Double.self, forKey: .recordingMinDelay) ?? 0.3
        recordingMaxDelay = try container.decodeIfPresent(Double.self, forKey: .recordingMaxDelay) ?? 5.0
        xcodeProjectPath = try container.decodeIfPresent(String.self, forKey: .xcodeProjectPath) ?? ""
        testTargetName = try container.decodeIfPresent(String.self, forKey: .testTargetName) ?? "iOSStressTestUITests"
        derivedDataPath = try container.decodeIfPresent(String.self, forKey: .derivedDataPath) ?? ""
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(defaultScreenWidth, forKey: .defaultScreenWidth)
        try container.encode(defaultScreenHeight, forKey: .defaultScreenHeight)
        try container.encode(screenshotRefreshInterval, forKey: .screenshotRefreshInterval)
        try container.encode(devicePollInterval, forKey: .devicePollInterval)
        try container.encode(defaultEventDelay, forKey: .defaultEventDelay)
        try container.encode(retryCount, forKey: .retryCount)
        try container.encode(commandTimeout, forKey: .commandTimeout)
        try container.encode(defaultSimilarityThreshold, forKey: .defaultSimilarityThreshold)
        try container.encode(imageScaleFactors, forKey: .imageScaleFactors)
        try container.encode(screenshotCacheExpiry, forKey: .screenshotCacheExpiry)
        try container.encode(screenshotSaveDir, forKey: .screenshotSaveDir)
        try container.encode(logLevel, forKey: .logLevel)
        try container.encode(maxLogFileSize, forKey: .maxLogFileSize)
        try container.encode(recordingAutoDelay, forKey: .recordingAutoDelay)
        try container.encode(recordingMinDelay, forKey: .recordingMinDelay)
        try container.encode(recordingMaxDelay, forKey: .recordingMaxDelay)
        try container.encode(xcodeProjectPath, forKey: .xcodeProjectPath)
        try container.encode(testTargetName, forKey: .testTargetName)
        try container.encode(derivedDataPath, forKey: .derivedDataPath)
    }

    // MARK: - 持久化

    private static var configURL: URL {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let dir = appSupport.appendingPathComponent("iOSStressTestTool")
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.appendingPathComponent("config.json")
    }

    static func load() -> AppConfig {
        guard let data = try? Data(contentsOf: configURL),
              let config = try? JSONDecoder().decode(AppConfig.self, from: data) else {
            return AppConfig()
        }
        return config
    }

    func save() {
        let encoder = JSONEncoder()
        encoder.outputFormatting = .prettyPrinted
        guard let data = try? encoder.encode(self) else { return }
        try? data.write(to: Self.configURL)
    }
}
