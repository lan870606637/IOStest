import Foundation

// MARK: - 设备会话管理
/// 一台设备复用一个 Appium 会话。会话创建代价高（真机 10–40 秒），
/// 任务执行期间必须复用，不能每条事件重建。
actor DeviceSessionManager {
    static let shared = DeviceSessionManager()

    private struct SessionRecord {
        let id: String
        let bundleId: String?
        let platformVersion: String?
    }

    private var records: [String: SessionRecord] = [:]
    private var inFlight: [String: Task<String, Error>] = [:]
    private var client: AppiumClient?

    // MARK: - 会话

    func ensureSession(udid: String,
                       bundleId: String?,
                       platformVersion: String?) async throws -> String {
        if let record = records[udid] {
            if let bundleId, record.bundleId != bundleId {
                // 目标 App 变了，旧会话不能复用。
                await closeSession(udid: udid)
            } else {
                return record.id
            }
        }

        if let existing = inFlight[udid] {
            return try await existing.value
        }

        let task = Task<String, Error> {
            try await self.createSession(udid: udid,
                                         bundleId: bundleId,
                                         platformVersion: platformVersion)
        }
        inFlight[udid] = task

        do {
            let sessionId = try await task.value
            records[udid] = SessionRecord(id: sessionId,
                                          bundleId: bundleId,
                                          platformVersion: platformVersion)
            inFlight[udid] = nil
            return sessionId
        } catch {
            inFlight[udid] = nil
            throw error
        }
    }

    private func createSession(udid: String,
                               bundleId: String?,
                               platformVersion: String?) async throws -> String {
        let client = try await activeClient()

        var capabilities: [String: Any] = [
            "platformName": "iOS",
            "appium:automationName": "XCUITest",
            "appium:udid": udid,
            "appium:noReset": true,
            "appium:newCommandTimeout": 600,
            "appium:wdaLaunchTimeout": 300_000,
            "appium:wdaConnectionTimeout": 300_000,
            "appium:derivedDataPath": HostEnvironment.derivedDataPath,
        ]
        if let bundleId, !bundleId.isEmpty {
            capabilities["appium:bundleId"] = bundleId
        }
        if let platformVersion, !platformVersion.isEmpty {
            capabilities["appium:platformVersion"] = platformVersion
        }

        Logger.shared.info("创建 Appium 会话: udid=\(udid), bundleId=\(bundleId ?? "-")")
        return try await client.createSession(capabilities)
    }

    func sessionId(for udid: String) -> String? {
        records[udid]?.id
    }

    func invalidate(udid: String) {
        records.removeValue(forKey: udid)
    }

    func closeSession(udid: String) async {
        guard let record = records.removeValue(forKey: udid) else { return }
        if let client {
            await client.deleteSession(record.id)
        }
    }

    func closeAll() async {
        let snapshot = records
        records.removeAll()
        inFlight.removeAll()
        guard let client else { return }
        for (_, record) in snapshot {
            await client.deleteSession(record.id)
        }
    }

    func shutdown() async {
        await closeAll()
        await AppiumServerManager.shared.stop()
    }

    // MARK: - 客户端

    /// 供 Backend 直接发命令；同时确保 Appium 服务已启动。
    func activeClient() async throws -> AppiumClient {
        let url = try await AppiumServerManager.shared.ensureRunning()
        if let client, client.baseURL == url {
            return client
        }
        let newClient = AppiumClient(baseURL: url)
        client = newClient
        return newClient
    }

    func activeSessionCount() -> Int {
        records.count
    }

    func activeSessions() -> [String: String] {
        records.mapValues { $0.id }
    }
}
