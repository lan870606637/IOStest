import Foundation

// MARK: - 设备类型
enum DeviceType: String, Codable {
    case simulator = "simulator"
    case physical = "physical"

    var displayName: String {
        switch self {
        case .simulator: return "模拟器"
        case .physical: return "真机"
        }
    }
}

// MARK: - 设备状态
enum DeviceStatus: String, Codable {
    case connected = "connected"
    case disconnected = "disconnected"
    case booting = "booting"
    case shuttingDown = "shutting_down"

    var displayName: String {
        switch self {
        case .connected: return "已连接"
        case .disconnected: return "未连接"
        case .booting: return "启动中"
        case .shuttingDown: return "关闭中"
        }
    }
}

// MARK: - 设备信息
struct DeviceInfo: Identifiable, Codable, Hashable {
    var id: String { udid }
    let udid: String
    var name: String
    var deviceType: DeviceType
    var status: DeviceStatus
    var osVersion: String
    var modelName: String
    var screenWidth: Int
    var screenHeight: Int
    var isAvailable: Bool
    /// devicectl 的 CoreDevice 标识符（用于 devices:// 实时预览 URL）
    var coreDeviceID: String? = nil

    var resolution: String {
        "\(screenWidth)x\(screenHeight)"
    }

    var displayTitle: String {
        "\(name) (\(osVersion)) - \(deviceType.displayName)"
    }

    func hash(into hasher: inout Hasher) {
        hasher.combine(udid)
    }

    static func == (lhs: DeviceInfo, rhs: DeviceInfo) -> Bool {
        lhs.udid == rhs.udid
    }
}
