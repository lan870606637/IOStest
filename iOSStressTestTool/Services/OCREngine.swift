import Foundation
import Vision
import AppKit

// MARK: - OCR 识别结果
struct OCRResult {
    let found: Bool
    let text: String
    let boundingBox: CGRect?       // 归一化坐标
    let centerPoint: CGPoint?      // 归一化中心点
    let confidence: Double
    let allResults: [OCRTextItem]
    let processingTime: TimeInterval
}

struct OCRTextItem: Identifiable {
    let id = UUID()
    let text: String
    let boundingBox: CGRect        // 归一化坐标
    let confidence: Double

    var centerPoint: CGPoint {
        CGPoint(x: boundingBox.midX, y: boundingBox.midY)
    }
}

// MARK: - OCR 引擎
/// 使用 Apple Vision 框架进行文字识别
final class OCREngine {
    static let shared = OCREngine()

    private let logger = Logger.shared

    private init() {}

    // MARK: - 全文识别

    /// 识别图像中所有文字
    func recognizeText(in image: NSImage, languages: [String] = ["zh-Hans", "zh-Hant", "en"]) async -> [OCRTextItem] {
        guard let cgImage = image.cgImage(forProposedRect: nil, context: nil, hints: nil) else {
            logger.error("OCR: 无法获取 CGImage")
            return []
        }

        return await withCheckedContinuation { continuation in
            let request = VNRecognizeTextRequest { request, error in
                if let error = error {
                    Logger.shared.error("OCR 识别失败: \(error)")
                    continuation.resume(returning: [])
                    return
                }

                let observations = request.results as? [VNRecognizedTextObservation] ?? []
                let items = observations.compactMap { obs -> OCRTextItem? in
                    guard let candidate = obs.topCandidates(1).first else { return nil }
                    return OCRTextItem(
                        text: candidate.string,
                        boundingBox: obs.boundingBox,
                        confidence: Double(candidate.confidence)
                    )
                }
                continuation.resume(returning: items)
            }

            request.recognitionLevel = .accurate
            request.recognitionLanguages = languages
            request.usesLanguageCorrection = true

            let handler = VNImageRequestHandler(cgImage: cgImage, options: [:])
            do {
                try handler.perform([request])
            } catch {
                Logger.shared.error("OCR handler 执行失败: \(error)")
                continuation.resume(returning: [])
            }
        }
    }

    // MARK: - 查找目标文字

    /// 在截图中查找指定文字
    func findText(
        _ targetText: String,
        in image: NSImage,
        fuzzyMatch: Bool = true
    ) async -> OCRResult {
        let startTime = Date()
        let allItems = await recognizeText(in: image)
        let elapsed = Date().timeIntervalSince(startTime)

        logger.debug("OCR 识别到 \(allItems.count) 个文本区域 (耗时: \(String(format: "%.2f", elapsed))s)")

        // 精确匹配
        if let exactMatch = allItems.first(where: { $0.text == targetText }) {
            return OCRResult(
                found: true,
                text: exactMatch.text,
                boundingBox: exactMatch.boundingBox,
                centerPoint: exactMatch.centerPoint,
                confidence: exactMatch.confidence,
                allResults: allItems,
                processingTime: elapsed
            )
        }

        // 模糊匹配
        if fuzzyMatch {
            // 包含匹配
            if let containsMatch = allItems.first(where: { $0.text.contains(targetText) || targetText.contains($0.text) }) {
                return OCRResult(
                    found: true,
                    text: containsMatch.text,
                    boundingBox: containsMatch.boundingBox,
                    centerPoint: containsMatch.centerPoint,
                    confidence: containsMatch.confidence * 0.9,
                    allResults: allItems,
                    processingTime: elapsed
                )
            }

            // 编辑距离匹配
            let bestFuzzy = allItems.min(by: {
                levenshteinDistance($0.text, targetText) < levenshteinDistance($1.text, targetText)
            })
            if let best = bestFuzzy {
                let distance = levenshteinDistance(best.text, targetText)
                let maxLen = max(best.text.count, targetText.count)
                let fuzzySimilarity = maxLen > 0 ? 1.0 - Double(distance) / Double(maxLen) : 0

                if fuzzySimilarity > 0.7 {
                    return OCRResult(
                        found: true,
                        text: best.text,
                        boundingBox: best.boundingBox,
                        centerPoint: best.centerPoint,
                        confidence: fuzzySimilarity,
                        allResults: allItems,
                        processingTime: elapsed
                    )
                }
            }
        }

        return OCRResult(
            found: false, text: "", boundingBox: nil, centerPoint: nil,
            confidence: 0, allResults: allItems, processingTime: elapsed
        )
    }

    // MARK: - 区域 OCR

    /// 识别截图中指定区域的文字
    func recognizeTextInRegion(
        image: NSImage,
        region: CGRect    // 归一化坐标
    ) async -> [OCRTextItem] {
        guard let cgImage = image.cgImage(forProposedRect: nil, context: nil, hints: nil) else { return [] }

        // 裁剪区域 (注意 Vision 坐标系 y 轴向上)
        let pixelRect = CGRect(
            x: region.origin.x * CGFloat(cgImage.width),
            y: (1.0 - region.origin.y - region.height) * CGFloat(cgImage.height),
            width: region.width * CGFloat(cgImage.width),
            height: region.height * CGFloat(cgImage.height)
        )

        guard let cropped = cgImage.cropping(to: pixelRect) else { return [] }

        let croppedImage = NSImage(cgImage: cropped, size: NSSize(width: cropped.width, height: cropped.height))
        return await recognizeText(in: croppedImage)
    }

    // MARK: - 辅助方法

    /// Vision 坐标转屏幕坐标 (Vision 的 y 轴向上，屏幕 y 轴向下)
    func visionToScreenCoordinates(
        boundingBox: CGRect,
        screenWidth: Int,
        screenHeight: Int
    ) -> (x: Int, y: Int) {
        let centerX = boundingBox.midX
        let centerY = 1.0 - boundingBox.midY  // 翻转 Y 轴

        return (
            x: Int(centerX * CGFloat(screenWidth)),
            y: Int(centerY * CGFloat(screenHeight))
        )
    }

    /// 编辑距离 (Levenshtein Distance)
    private func levenshteinDistance(_ s1: String, _ s2: String) -> Int {
        let a = Array(s1)
        let b = Array(s2)
        let m = a.count
        let n = b.count

        if m == 0 { return n }
        if n == 0 { return m }

        var dp = Array(repeating: Array(repeating: 0, count: n + 1), count: m + 1)

        for i in 0...m { dp[i][0] = i }
        for j in 0...n { dp[0][j] = j }

        for i in 1...m {
            for j in 1...n {
                if a[i - 1] == b[j - 1] {
                    dp[i][j] = dp[i - 1][j - 1]
                } else {
                    dp[i][j] = min(dp[i - 1][j], dp[i][j - 1], dp[i - 1][j - 1]) + 1
                }
            }
        }

        return dp[m][n]
    }
}
