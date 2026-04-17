import Foundation
import Combine

// MARK: - 设备视图模型
final class DeviceViewModel: ObservableObject {
    @Published var devices: [DeviceInfo] = []
    @Published var selectedDevice: DeviceInfo?
    @Published var isRefreshing = false
    @Published var filterType: DeviceFilterType = .all
    @Published var statusMessage = ""

    private let deviceService = DeviceService.shared
    private let logger = Logger.shared
    private var cancellables = Set<AnyCancellable>()

    enum DeviceFilterType: String, CaseIterable {
        case all = "全部"
        case simulator = "模拟器"
        case physical = "真机"
        case connected = "已连接"
    }

    var filteredDevices: [DeviceInfo] {
        switch filterType {
        case .all: return devices
        case .simulator: return devices.filter { $0.deviceType == .simulator }
        case .physical: return devices.filter { $0.deviceType == .physical }
        case .connected: return devices.filter { $0.status == .connected }
        }
    }

    var connectedDeviceCount: Int {
        devices.filter { $0.status == .connected }.count
    }

    init() {
        // 同步设备服务的数据
        deviceService.$devices
            .receive(on: DispatchQueue.main)
            .assign(to: &$devices)

        deviceService.$selectedDevice
            .receive(on: DispatchQueue.main)
            .assign(to: &$selectedDevice)
    }

    // MARK: - 设备操作

    func refreshDevices() async {
        await MainActor.run {
            isRefreshing = true
            statusMessage = "正在刷新设备列表..."
        }

        await deviceService.refreshDevices()

        await MainActor.run {
            isRefreshing = false
            statusMessage = "已发现 \(devices.count) 台设备，\(connectedDeviceCount) 台已连接"
        }
    }

    func selectDevice(_ device: DeviceInfo) {
        selectedDevice = device
        deviceService.selectedDevice = device
        logger.info("选中设备: \(device.displayTitle)")
    }

    func bootSimulator(_ device: DeviceInfo) async {
        guard device.deviceType == .simulator else { return }
        await MainActor.run { statusMessage = "正在启动模拟器: \(device.name)..." }

        let success = await deviceService.bootSimulator(udid: device.udid)

        await MainActor.run {
            statusMessage = success ? "模拟器已启动: \(device.name)" : "模拟器启动失败"
        }
    }

    func shutdownSimulator(_ device: DeviceInfo) async {
        guard device.deviceType == .simulator else { return }
        let success = await deviceService.shutdownSimulator(udid: device.udid)
        await MainActor.run {
            statusMessage = success ? "模拟器已关闭" : "模拟器关闭失败"
        }
    }

    func startPolling() {
        deviceService.startPolling(interval: AppConfig.shared.devicePollInterval)
    }

    func stopPolling() {
        deviceService.stopPolling()
    }

    // MARK: - 应用管理

    func installApp(appPath: String) async {
        guard let device = selectedDevice else {
            statusMessage = "请先选择设备"
            return
        }
        let success = await deviceService.installApp(udid: device.udid, appPath: appPath)
        await MainActor.run {
            statusMessage = success ? "应用安装成功" : "应用安装失败"
        }
    }

    func launchApp(bundleId: String) async {
        guard let device = selectedDevice else { return }
        let success = await deviceService.launchApp(udid: device.udid, bundleId: bundleId)
        await MainActor.run {
            statusMessage = success ? "应用已启动" : "应用启动失败"
        }
    }

    func terminateApp(bundleId: String) async {
        guard let device = selectedDevice else { return }
        let success = await deviceService.terminateApp(udid: device.udid, bundleId: bundleId)
        await MainActor.run {
            statusMessage = success ? "应用已终止" : "应用终止失败"
        }
    }
}
