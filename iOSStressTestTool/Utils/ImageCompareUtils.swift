import Foundation
import CoreImage
import CoreGraphics
import AppKit

// MARK: - 图像比较结果
struct ImageCompareResult {
    let similarity: Double      // 0.0 ~ 1.0
    let matchFound: Bool
    let matchRegion: CGRect?
    let method: String
    let processingTime: TimeInterval
}

// MARK: - 图像比较工具
final class ImageCompareUtils {
    static let shared = ImageCompareUtils()
    private let logger = Logger.shared

    private init() {}

    // MARK: - 直方图比较

    func compareHistogram(image1: CGImage, image2: CGImage) -> Double {
        let hist1 = calculateHistogram(image: image1)
        let hist2 = calculateHistogram(image: image2)

        guard hist1.count == hist2.count, !hist1.isEmpty else { return 0 }

        // 巴氏距离
        var similarity: Double = 0
        for i in 0..<hist1.count {
            similarity += sqrt(hist1[i] * hist2[i])
        }
        return similarity
    }

    private func calculateHistogram(image: CGImage) -> [Double] {
        guard let data = image.dataProvider?.data,
              let ptr = CFDataGetBytePtr(data) else { return [] }

        let bytesPerPixel = image.bitsPerPixel / 8
        let totalPixels = image.width * image.height
        var histogram = [Double](repeating: 0, count: 256)

        for i in 0..<totalPixels {
            let offset = i * bytesPerPixel
            let gray = (Int(ptr[offset]) + Int(ptr[offset + 1]) + Int(ptr[offset + 2])) / 3
            histogram[gray] += 1
        }

        // 归一化
        let total = Double(totalPixels)
        return histogram.map { $0 / total }
    }

    // MARK: - 像素级比较

    func comparePixels(image1: CGImage, image2: CGImage, excludeStatusBar: Bool = true) -> Double {
        guard image1.width == image2.width, image1.height == image2.height else {
            logger.warning("图像尺寸不匹配: \(image1.width)x\(image1.height) vs \(image2.width)x\(image2.height)")
            return 0
        }

        guard let data1 = image1.dataProvider?.data,
              let data2 = image2.dataProvider?.data,
              let ptr1 = CFDataGetBytePtr(data1),
              let ptr2 = CFDataGetBytePtr(data2) else { return 0 }

        let bytesPerPixel = image1.bitsPerPixel / 8
        let width = image1.width
        let height = image1.height
        let startY = excludeStatusBar ? Int(Double(height) * 0.05) : 0

        var matchCount = 0
        var totalCount = 0

        for y in startY..<height {
            for x in 0..<width {
                let offset = (y * width + x) * bytesPerPixel
                let diff = abs(Int(ptr1[offset]) - Int(ptr2[offset]))
                    + abs(Int(ptr1[offset + 1]) - Int(ptr2[offset + 1]))
                    + abs(Int(ptr1[offset + 2]) - Int(ptr2[offset + 2]))
                if diff < 30 { matchCount += 1 }
                totalCount += 1
            }
        }

        return totalCount > 0 ? Double(matchCount) / Double(totalCount) : 0
    }

    // MARK: - SSIM 结构相似性

    func compareSSIM(image1: CGImage, image2: CGImage) -> Double {
        guard image1.width == image2.width, image1.height == image2.height else { return 0 }

        guard let data1 = image1.dataProvider?.data,
              let data2 = image2.dataProvider?.data,
              let ptr1 = CFDataGetBytePtr(data1),
              let ptr2 = CFDataGetBytePtr(data2) else { return 0 }

        let bytesPerPixel = image1.bitsPerPixel / 8
        let count = image1.width * image1.height

        var mean1: Double = 0, mean2: Double = 0
        for i in 0..<count {
            let offset = i * bytesPerPixel
            mean1 += Double(ptr1[offset])
            mean2 += Double(ptr2[offset])
        }
        mean1 /= Double(count)
        mean2 /= Double(count)

        var var1: Double = 0, var2: Double = 0, covar: Double = 0
        for i in 0..<count {
            let offset = i * bytesPerPixel
            let d1 = Double(ptr1[offset]) - mean1
            let d2 = Double(ptr2[offset]) - mean2
            var1 += d1 * d1
            var2 += d2 * d2
            covar += d1 * d2
        }
        var1 /= Double(count)
        var2 /= Double(count)
        covar /= Double(count)

        let c1 = 6.5025   // (0.01 * 255)^2
        let c2 = 58.5225  // (0.03 * 255)^2

        let numerator = (2 * mean1 * mean2 + c1) * (2 * covar + c2)
        let denominator = (mean1 * mean1 + mean2 * mean2 + c1) * (var1 + var2 + c2)

        return numerator / denominator
    }

    // MARK: - 综合比较

    func compare(image1: CGImage, image2: CGImage, method: String = "pixel") -> ImageCompareResult {
        let start = Date()
        let similarity: Double

        switch method {
        case "histogram":
            similarity = compareHistogram(image1: image1, image2: image2)
        case "ssim":
            similarity = compareSSIM(image1: image1, image2: image2)
        default:
            similarity = comparePixels(image1: image1, image2: image2)
        }

        return ImageCompareResult(
            similarity: similarity,
            matchFound: similarity > 0.8,
            matchRegion: nil,
            method: method,
            processingTime: Date().timeIntervalSince(start)
        )
    }

    // MARK: - 工具方法

    func loadImage(from path: String) -> CGImage? {
        guard let nsImage = NSImage(contentsOfFile: path),
              let cgImage = nsImage.cgImage(forProposedRect: nil, context: nil, hints: nil) else {
            logger.error("无法加载图像: \(path)")
            return nil
        }
        return cgImage
    }

    func resizeImage(_ image: CGImage, to size: CGSize) -> CGImage? {
        let context = CGContext(
            data: nil,
            width: Int(size.width),
            height: Int(size.height),
            bitsPerComponent: 8,
            bytesPerRow: 0,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        )
        context?.interpolationQuality = .high
        context?.draw(image, in: CGRect(origin: .zero, size: size))
        return context?.makeImage()
    }
}
