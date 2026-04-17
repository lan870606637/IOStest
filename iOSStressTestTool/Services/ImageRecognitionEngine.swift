import Foundation
import Vision
import AppKit
import CoreImage

// MARK: - 图像识别结果
struct RecognitionResult {
    let found: Bool
    let confidence: Double
    let matchRect: CGRect?         // 归一化坐标 (0~1)
    let centerPoint: CGPoint?      // 归一化中心点
    let processingTime: TimeInterval
    let scaleUsed: Double?
}

// MARK: - 图像识别引擎
/// 使用 Apple Vision 框架进行模板匹配和图像识别
final class ImageRecognitionEngine {
    static let shared = ImageRecognitionEngine()

    private let logger = Logger.shared
    private let config = AppConfig.shared

    private init() {}

    // MARK: - 模板匹配 (Vision Feature Print)

    /// 在屏幕截图中查找模板图像
    func findTemplate(
        templatePath: String,
        in screenshotImage: NSImage,
        similarityThreshold: Double = 0.8
    ) async -> RecognitionResult {
        let startTime = Date()

        guard let templateNS = NSImage(contentsOfFile: templatePath),
              let templateCG = templateNS.cgImage(forProposedRect: nil, context: nil, hints: nil),
              let screenshotCG = screenshotImage.cgImage(forProposedRect: nil, context: nil, hints: nil) else {
            logger.error("无法加载模板或截图图像")
            return RecognitionResult(found: false, confidence: 0, matchRect: nil,
                                     centerPoint: nil, processingTime: Date().timeIntervalSince(startTime), scaleUsed: nil)
        }

        // 多尺度模板匹配
        for scale in config.imageScaleFactors {
            let scaledTemplate = scaleImage(templateCG, by: scale)
            guard let scaled = scaledTemplate else { continue }

            if let result = await performTemplateMatch(template: scaled, screenshot: screenshotCG, threshold: similarityThreshold) {
                let elapsed = Date().timeIntervalSince(startTime)
                logger.info("模板匹配成功 (scale=\(scale), confidence=\(String(format: "%.2f", result.confidence)))")
                return RecognitionResult(
                    found: true,
                    confidence: result.confidence,
                    matchRect: result.rect,
                    centerPoint: CGPoint(
                        x: result.rect.midX,
                        y: result.rect.midY
                    ),
                    processingTime: elapsed,
                    scaleUsed: scale
                )
            }
        }

        let elapsed = Date().timeIntervalSince(startTime)
        logger.info("模板匹配未找到 (耗时: \(String(format: "%.2f", elapsed))s)")
        return RecognitionResult(found: false, confidence: 0, matchRect: nil,
                                 centerPoint: nil, processingTime: elapsed, scaleUsed: nil)
    }

    /// 使用 Vision 的 VNTranslationalImageRegistrationRequest 进行匹配
    private func performTemplateMatch(
        template: CGImage,
        screenshot: CGImage,
        threshold: Double
    ) async -> (rect: CGRect, confidence: Double)? {
        // 滑动窗口模板匹配
        let templateW = template.width
        let templateH = template.height
        let screenshotW = screenshot.width
        let screenshotH = screenshot.height

        guard templateW <= screenshotW, templateH <= screenshotH else { return nil }

        // 使用 VNImageRegistration 进行区域匹配
        let stepX = max(templateW / 4, 20)
        let stepY = max(templateH / 4, 20)

        var bestMatch: (rect: CGRect, confidence: Double)?

        for y in stride(from: 0, through: screenshotH - templateH, by: stepY) {
            for x in stride(from: 0, through: screenshotW - templateW, by: stepX) {
                let cropRect = CGRect(x: x, y: y, width: templateW, height: templateH)
                guard let cropped = screenshot.cropping(to: cropRect) else { continue }

                let similarity = calculateSimilarity(image1: template, image2: cropped)
                if similarity >= threshold {
                    let normalizedRect = CGRect(
                        x: Double(x) / Double(screenshotW),
                        y: Double(y) / Double(screenshotH),
                        width: Double(templateW) / Double(screenshotW),
                        height: Double(templateH) / Double(screenshotH)
                    )

                    if bestMatch == nil || similarity > bestMatch!.confidence {
                        bestMatch = (rect: normalizedRect, confidence: similarity)
                    }
                }
            }
        }

        return bestMatch
    }

    /// 使用 Vision FeaturePrint 计算两张图像的相似度
    private func calculateSimilarity(image1: CGImage, image2: CGImage) -> Double {
        var similarity: Float = 0

        let request1 = VNGenerateImageFeaturePrintRequest()
        let request2 = VNGenerateImageFeaturePrintRequest()

        let handler1 = VNImageRequestHandler(cgImage: image1, options: [:])
        let handler2 = VNImageRequestHandler(cgImage: image2, options: [:])

        do {
            try handler1.perform([request1])
            try handler2.perform([request2])

            guard let fp1 = request1.results?.first as? VNFeaturePrintObservation,
                  let fp2 = request2.results?.first as? VNFeaturePrintObservation else { return 0 }

            try fp1.computeDistance(&similarity, to: fp2)

            // VNFeaturePrint distance 越小越相似，转换为 0~1 相似度
            return Double(max(0, 1.0 - similarity / 20.0))
        } catch {
            return 0
        }
    }

    // MARK: - 辅助方法

    private func scaleImage(_ image: CGImage, by scale: Double) -> CGImage? {
        guard scale != 1.0 else { return image }
        let newWidth = Int(Double(image.width) * scale)
        let newHeight = Int(Double(image.height) * scale)
        guard newWidth > 0, newHeight > 0 else { return nil }

        guard let context = CGContext(
            data: nil,
            width: newWidth, height: newHeight,
            bitsPerComponent: 8,
            bytesPerRow: 0,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else { return nil }

        context.interpolationQuality = .high
        context.draw(image, in: CGRect(x: 0, y: 0, width: newWidth, height: newHeight))
        return context.makeImage()
    }

    /// 将归一化坐标转换为设备绝对坐标
    func normalizedToDeviceCoordinates(
        point: CGPoint,
        deviceWidth: Int,
        deviceHeight: Int
    ) -> (x: Int, y: Int) {
        return (
            x: Int(point.x * CGFloat(deviceWidth)),
            y: Int(point.y * CGFloat(deviceHeight))
        )
    }
}
