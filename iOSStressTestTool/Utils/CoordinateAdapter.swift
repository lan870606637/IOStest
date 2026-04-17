import Foundation
import CoreGraphics

// MARK: - 坐标适配器
/// 处理不同 iOS 设备分辨率之间的坐标转换
final class CoordinateAdapter {
    static let shared = CoordinateAdapter()
    private let logger = Logger.shared

    // 常见 iOS 设备逻辑分辨率 (points)
    static let knownResolutions: [(name: String, width: Int, height: Int, scale: Int)] = [
        ("iPhone SE (3rd)", 375, 667, 2),
        ("iPhone 14", 390, 844, 3),
        ("iPhone 14 Plus", 428, 926, 3),
        ("iPhone 14 Pro", 393, 852, 3),
        ("iPhone 14 Pro Max", 430, 932, 3),
        ("iPhone 15", 393, 852, 3),
        ("iPhone 15 Plus", 430, 932, 3),
        ("iPhone 15 Pro", 393, 852, 3),
        ("iPhone 15 Pro Max", 430, 932, 3),
        ("iPhone 16", 393, 852, 3),
        ("iPhone 16 Pro", 402, 874, 3),
        ("iPhone 16 Pro Max", 440, 956, 3),
        ("iPad Air (5th)", 820, 1180, 2),
        ("iPad Pro 11\"", 834, 1194, 2),
        ("iPad Pro 12.9\"", 1024, 1366, 2),
    ]

    private init() {}

    // MARK: - 坐标转换

    /// 将源分辨率的坐标转换到目标分辨率
    func adaptCoordinate(
        x: Int, y: Int,
        fromWidth: Int, fromHeight: Int,
        toWidth: Int, toHeight: Int
    ) -> (x: Int, y: Int) {
        let ratioX = Double(toWidth) / Double(fromWidth)
        let ratioY = Double(toHeight) / Double(fromHeight)

        let newX = Int(Double(x) * ratioX)
        let newY = Int(Double(y) * ratioY)

        return (x: min(newX, toWidth - 1), y: min(newY, toHeight - 1))
    }

    /// 将相对坐标 (0.0~1.0) 转换为绝对坐标
    func relativeToAbsolute(relX: Double, relY: Double, width: Int, height: Int) -> (x: Int, y: Int) {
        let absX = Int(relX * Double(width))
        let absY = Int(relY * Double(height))
        return (x: min(absX, width - 1), y: min(absY, height - 1))
    }

    /// 将绝对坐标转换为相对坐标
    func absoluteToRelative(x: Int, y: Int, width: Int, height: Int) -> (relX: Double, relY: Double) {
        let relX = Double(x) / Double(width)
        let relY = Double(y) / Double(height)
        return (relX: min(relX, 1.0), relY: min(relY, 1.0))
    }

    // MARK: - 像素坐标与点坐标转换

    /// 像素坐标转点坐标 (考虑 Retina 缩放)
    func pixelsToPoints(x: Int, y: Int, scale: Int) -> (x: Int, y: Int) {
        return (x: x / scale, y: y / scale)
    }

    /// 点坐标转像素坐标
    func pointsToPixels(x: Int, y: Int, scale: Int) -> (x: Int, y: Int) {
        return (x: x * scale, y: y * scale)
    }

    // MARK: - 截图坐标映射

    /// 将预览画面上的点击坐标映射到设备实际坐标
    func mapPreviewToDevice(
        previewPoint: CGPoint,
        previewSize: CGSize,
        deviceWidth: Int,
        deviceHeight: Int
    ) -> (x: Int, y: Int) {
        let scaleX = CGFloat(deviceWidth) / previewSize.width
        let scaleY = CGFloat(deviceHeight) / previewSize.height

        let deviceX = Int(previewPoint.x * scaleX)
        let deviceY = Int(previewPoint.y * scaleY)

        return (
            x: max(0, min(deviceX, deviceWidth - 1)),
            y: max(0, min(deviceY, deviceHeight - 1))
        )
    }

    // MARK: - 安全区域

    /// 获取设备安全区域 (避免状态栏/Home指示器)
    func safeArea(for deviceName: String, width: Int, height: Int) -> (top: Int, bottom: Int) {
        // Face ID 设备
        if deviceName.contains("Pro") || deviceName.contains("15") || deviceName.contains("16") || deviceName.contains("14") {
            return (top: 59, bottom: 34) // 刘海/灵动岛设备
        }
        // Touch ID 设备
        if deviceName.contains("SE") {
            return (top: 20, bottom: 0)
        }
        // iPad
        if deviceName.contains("iPad") {
            return (top: 24, bottom: 20)
        }
        // 默认
        return (top: 47, bottom: 34)
    }
}
