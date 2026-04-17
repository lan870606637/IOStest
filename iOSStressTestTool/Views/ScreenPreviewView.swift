import SwiftUI

// MARK: - 屏幕预览视图
struct ScreenPreviewView: View {
    @ObservedObject var deviceVM: DeviceViewModel
    @ObservedObject var recordingVM: RecordingViewModel

    @StateObject private var screenshotService = ScreenshotService.shared

    @State private var previewImage: NSImage?
    @State private var isAutoRefreshing = false
    @State private var refreshTimer: Timer?
    @State private var lastTapCoordinate: String = ""
    @State private var refreshInterval: Double = 1.0

    // 拖拽状态
    @State private var dragStart: CGPoint?
    @State private var dragEnd: CGPoint?
    @State private var isDragging = false
    @State private var pressStartTime: Date?

    var body: some View {
        VStack(spacing: 0) {
            // 工具栏
            HStack {
                Text("屏幕预览")
                    .font(.title2.bold())
                Spacer()

                if let device = deviceVM.selectedDevice {
                    Text(device.displayTitle)
                        .font(.caption)
                        .foregroundColor(.secondary)
                }

                Divider().frame(height: 20)

                Toggle("自动刷新", isOn: $isAutoRefreshing)
                    .toggleStyle(.switch)
                    .onChange(of: isAutoRefreshing) { _, newValue in
                        if newValue { startAutoRefresh() } else { stopAutoRefresh() }
                    }

                Stepper("间隔 \(String(format: "%.1f", refreshInterval))s",
                        value: $refreshInterval, in: 0.5...10, step: 0.5)
                    .frame(width: 160)

                Button(action: { captureScreenshot() }) {
                    Label("截图", systemImage: "camera")
                }
            }
            .padding()
            .background(Color(nsColor: .controlBackgroundColor))

            Divider()

            // 预览区域
            HStack(spacing: 0) {
                // 设备屏幕预览
                GeometryReader { geometry in
                    ZStack {
                        if let image = previewImage {
                            Image(nsImage: image)
                                .resizable()
                                .aspectRatio(contentMode: .fit)
                                .frame(maxWidth: geometry.size.width * 0.7, maxHeight: geometry.size.height)
                                .background(Color.black)
                                .cornerRadius(12)
                                .shadow(radius: 5)
                                .gesture(tapAndDragGesture(in: geometry.size))
                                .overlay(dragOverlay)
                        } else {
                            VStack(spacing: 12) {
                                Image(systemName: "iphone")
                                    .font(.system(size: 64))
                                    .foregroundColor(.secondary)
                                Text(deviceVM.selectedDevice == nil ? "请先选择设备" : "点击截图按钮获取屏幕画面")
                                    .foregroundColor(.secondary)
                            }
                        }
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                }

                Divider()

                // 右侧操作面板
                VStack(alignment: .leading, spacing: 12) {
                    GroupBox("坐标信息") {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(lastTapCoordinate.isEmpty ? "点击预览画面获取坐标" : lastTapCoordinate)
                                .font(.system(.body, design: .monospaced))
                                .foregroundColor(.primary)
                        }
                        .padding(4)
                    }

                    GroupBox("快捷操作") {
                        VStack(spacing: 8) {
                            HStack(spacing: 8) {
                                hardwareButton("Home", icon: "house", type: .homeButton)
                                hardwareButton("锁屏", icon: "lock", type: .lockScreen)
                            }
                            HStack(spacing: 8) {
                                hardwareButton("音量+", icon: "speaker.plus", type: .volumeUp)
                                hardwareButton("音量-", icon: "speaker.minus", type: .volumeDown)
                            }
                            HStack(spacing: 8) {
                                hardwareButton("摇晃", icon: "iphone.radiowaves.left.and.right", type: .shake)
                            }
                        }
                        .padding(4)
                    }

                    if recordingVM.state == .recording {
                        GroupBox("录制中") {
                            VStack(alignment: .leading, spacing: 4) {
                                HStack {
                                    Circle().fill(.red).frame(width: 8, height: 8)
                                    Text(recordingVM.formattedTime)
                                        .font(.system(.body, design: .monospaced))
                                }
                                Text("事件数: \(recordingVM.eventCount)")
                                    .font(.caption)
                            }
                            .padding(4)
                        }
                    }

                    Spacer()
                }
                .frame(width: 200)
                .padding()
            }
        }
        .onDisappear {
            stopAutoRefresh()
        }
    }

    // MARK: - 手势处理

    private func tapAndDragGesture(in size: CGSize) -> some Gesture {
        DragGesture(minimumDistance: 0)
            .onChanged { value in
                if dragStart == nil {
                    dragStart = value.startLocation
                    pressStartTime = Date()
                }
                dragEnd = value.location
                isDragging = true
            }
            .onEnded { value in
                guard let start = dragStart, let device = deviceVM.selectedDevice else {
                    resetDrag()
                    return
                }

                let pressDuration = Date().timeIntervalSince(pressStartTime ?? Date())
                let distance = hypot(value.location.x - start.x, value.location.y - start.y)

                // 计算预览图在 geometry 中的实际大小
                let imageAspect = CGFloat(device.screenWidth) / CGFloat(device.screenHeight)
                let previewWidth = min(size.width * 0.7, size.height * imageAspect)
                let previewHeight = previewWidth / imageAspect
                let previewSize = CGSize(width: previewWidth, height: previewHeight)

                let adapter = CoordinateAdapter.shared

                if distance < 10 {
                    // 点击
                    let coords = adapter.mapPreviewToDevice(
                        previewPoint: start,
                        previewSize: previewSize,
                        deviceWidth: device.screenWidth,
                        deviceHeight: device.screenHeight
                    )

                    lastTapCoordinate = "点击: (\(coords.x), \(coords.y))"

                    if pressDuration > 0.5 {
                        // 长按
                        if recordingVM.state == .recording {
                            recordingVM.recordLongPress(x: coords.x, y: coords.y, duration: pressDuration)
                        }
                        Task { await DeviceService.shared.longPress(udid: device.udid, x: coords.x, y: coords.y, duration: pressDuration) }
                    } else {
                        // 单击
                        if recordingVM.state == .recording {
                            recordingVM.recordTap(x: coords.x, y: coords.y)
                        }
                        Task { await DeviceService.shared.tap(udid: device.udid, x: coords.x, y: coords.y) }
                    }
                } else {
                    // 滑动
                    let startCoords = adapter.mapPreviewToDevice(
                        previewPoint: start,
                        previewSize: previewSize,
                        deviceWidth: device.screenWidth,
                        deviceHeight: device.screenHeight
                    )
                    let endCoords = adapter.mapPreviewToDevice(
                        previewPoint: value.location,
                        previewSize: previewSize,
                        deviceWidth: device.screenWidth,
                        deviceHeight: device.screenHeight
                    )

                    lastTapCoordinate = "滑动: (\(startCoords.x),\(startCoords.y)) -> (\(endCoords.x),\(endCoords.y))"

                    if recordingVM.state == .recording {
                        recordingVM.recordSwipe(
                            startX: startCoords.x, startY: startCoords.y,
                            endX: endCoords.x, endY: endCoords.y,
                            duration: pressDuration
                        )
                    }
                    Task {
                        await DeviceService.shared.swipe(
                            udid: device.udid,
                            startX: startCoords.x, startY: startCoords.y,
                            endX: endCoords.x, endY: endCoords.y,
                            duration: min(pressDuration, 2.0)
                        )
                    }
                }

                resetDrag()
                // 刷新截图
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { captureScreenshot() }
            }
    }

    @ViewBuilder
    private var dragOverlay: some View {
        if isDragging, let start = dragStart, let end = dragEnd {
            let distance = hypot(end.x - start.x, end.y - start.y)
            if distance > 10 {
                Path { path in
                    path.move(to: start)
                    path.addLine(to: end)
                }
                .stroke(Color.orange, lineWidth: 2)
                .allowsHitTesting(false)
            }
        }
    }

    private func resetDrag() {
        dragStart = nil
        dragEnd = nil
        isDragging = false
        pressStartTime = nil
    }

    // MARK: - 硬件按钮

    private func hardwareButton(_ title: String, icon: String, type: EventType) -> some View {
        Button(action: {
            guard let device = deviceVM.selectedDevice else { return }
            if recordingVM.state == .recording {
                recordingVM.recordHardwareButton(type)
            }
            Task {
                switch type {
                case .homeButton: _ = await DeviceService.shared.pressHome(udid: device.udid)
                case .lockScreen: _ = await DeviceService.shared.lockScreen(udid: device.udid)
                case .volumeUp: _ = await DeviceService.shared.pressVolumeUp(udid: device.udid)
                case .volumeDown: _ = await DeviceService.shared.pressVolumeDown(udid: device.udid)
                case .shake: _ = await DeviceService.shared.shake(udid: device.udid)
                default: break
                }
                captureScreenshot()
            }
        }) {
            Label(title, systemImage: icon)
                .frame(maxWidth: .infinity)
        }
        .disabled(deviceVM.selectedDevice == nil)
    }

    // MARK: - 截图与刷新

    private func captureScreenshot() {
        guard let device = deviceVM.selectedDevice else { return }
        Task {
            screenshotService.invalidateCache(for: device.udid)
            if let image = await screenshotService.captureScreenshot(deviceUDID: device.udid, deviceType: device.deviceType) {
                await MainActor.run { previewImage = image }
            }
        }
    }

    private func startAutoRefresh() {
        stopAutoRefresh()
        refreshTimer = Timer.scheduledTimer(withTimeInterval: refreshInterval, repeats: true) { _ in
            captureScreenshot()
        }
        captureScreenshot()
    }

    private func stopAutoRefresh() {
        refreshTimer?.invalidate()
        refreshTimer = nil
    }
}
