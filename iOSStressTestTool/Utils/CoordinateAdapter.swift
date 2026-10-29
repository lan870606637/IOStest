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

    // 常见真机 productType 逻辑分辨率 (points)
    static let productTypeResolutions: [String: (width: Int, height: Int)] = [
        "iPhone9,1": (375, 667),  // iPhone 6s
        "iPhone9,2": (414, 736),  // iPhone 6s Plus
        "iPhone9,3": (375, 667),  // iPhone 7
        "iPhone9,4": (414, 736),  // iPhone 7 Plus
        "iPhone10,1": (375, 667), // iPhone 8
        "iPhone10,2": (414, 736), // iPhone 8 Plus
        "iPhone10,3": (375, 812), // iPhone X
        "iPhone10,4": (375, 667), // iPhone 8
        "iPhone10,5": (414, 736), // iPhone 8 Plus
        "iPhone10,6": (375, 812), // iPhone X
        "iPhone11,2": (375, 812), // iPhone XS
        "iPhone11,4": (414, 896), // iPhone XS Max
        "iPhone11,6": (414, 896), // iPhone XS Max
        "iPhone11,8": (414, 896), // iPhone XR
        "iPhone12,1": (414, 896), // iPhone 11
        "iPhone12,3": (375, 812), // iPhone 11 Pro
        "iPhone12,5": (414, 896), // iPhone 11 Pro Max
        "iPhone12,8": (375, 667), // iPhone SE (2nd)
        "iPhone13,1": (360, 780), // iPhone 12 mini
        "iPhone13,2": (390, 844), // iPhone 12
        "iPhone13,3": (390, 844), // iPhone 12 Pro
        "iPhone13,4": (428, 926), // iPhone 12 Pro Max
        "iPhone14,2": (390, 844), // iPhone 13 Pro
        "iPhone14,3": (428, 926), // iPhone 13 Pro Max
        "iPhone14,4": (375, 812), // iPhone 13 mini
        "iPhone14,5": (390, 844), // iPhone 13
        "iPhone14,6": (375, 667), // iPhone SE (3rd)
        "iPhone14,7": (390, 844), // iPhone 14
        "iPhone14,8": (428, 926), // iPhone 14 Plus
        "iPhone15,2": (393, 852), // iPhone 14 Pro
        "iPhone15,3": (430, 932), // iPhone 14 Pro Max
        "iPhone15,4": (393, 852), // iPhone 15
        "iPhone15,5": (430, 932), // iPhone 15 Plus
        "iPhone16,1": (393, 852), // iPhone 15 Pro
        "iPhone16,2": (430, 932), // iPhone 15 Pro Max
        "iPhone17,1": (402, 874), // iPhone 16 Pro
        "iPhone17,2": (440, 956), // iPhone 16 Pro Max
        "iPhone17,3": (393, 852), // iPhone 16
        "iPhone17,4": (430, 932), // iPhone 16 Plus
    ]

    /// 根据真机 productType (如 iPhone11,6) 获取逻辑分辨率
    static func resolution(forProductType productType: String) -> (width: Int, height: Int)? {
        productTypeResolutions[productType]
    }

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
