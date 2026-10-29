import Foundation

// MARK: - 控件定位策略
enum LocatorStrategy: String, Codable, CaseIterable, Identifiable {
    case accessibilityId = "accessibility_id"
    case label = "label"
    case predicate = "predicate"
    case classChain = "class_chain"
    case xpath = "xpath"
    case point = "point"

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .accessibilityId: return "accessibility id"
        case .label: return "文字 (label)"
        case .predicate: return "Predicate"
        case .classChain: return "Class Chain"
        case .xpath: return "XPath"
        case .point: return "坐标点"
        }
    }

    /// Appium 的 locator strategy 名称；坐标点不参与元素查找。
    var appiumUsing: String? {
        switch self {
        case .accessibilityId: return "accessibility id"
        case .label, .predicate: return "-ios predicate string"
        case .classChain: return "-ios class chain"
        case .xpath: return "xpath"
        case .point: return nil
        }
    }

    var supportsIndex: Bool {
        switch self {
        case .point: return false
        default: return true
        }
    }

    var placeholder: String {
        switch self {
        case .accessibilityId: return "例如 login_button"
        case .label: return "例如 登录"
        case .predicate: return "例如 label == \"登录\" AND type == \"Button\""
        case .classChain: return "例如 **/XCUIElementTypeButton[`label == \"登录\"`]"
        case .xpath: return "例如 //XCUIElementTypeButton[@name=\"login_button\"]"
        case .point: return "使用下方的 x / y 坐标"
        }
    }

    var helpText: String {
        switch self {
        case .accessibilityId:
            return "最稳的方式。需要 App 给控件设置 accessibilityIdentifier（SwiftUI 用 .accessibilityIdentifier）。"
        case .label:
            return "按控件显示文字匹配，适合按钮、Cell、Tab。文字变化会导致失败。"
        case .predicate:
            return "NSPredicate 语法，可按 label/name/value/type 组合匹配，比 XPath 快。"
        case .classChain:
            return "XCUITest 原生层级查询，性能最好，适合复杂页面。"
        case .xpath:
            return "兼容性最好但最慢，只建议兜底使用。"
        case .point:
            return "不查找控件，直接按屏幕坐标（point，不是像素）点击。"
        }
    }
}

// MARK: - 控件定位描述
struct Locator: Codable, Equatable, Hashable {
    var strategy: LocatorStrategy
    var value: String
    var index: Int?
    var timeout: Double
    var x: Int?
    var y: Int?

    init(strategy: LocatorStrategy = .accessibilityId,
         value: String = "",
         index: Int? = nil,
         timeout: Double = 5.0,
         x: Int? = nil,
         y: Int? = nil) {
        self.strategy = strategy
        self.value = value
        self.index = index
        self.timeout = timeout
        self.x = x
        self.y = y
    }

    var isUsable: Bool {
        if strategy == .point {
            return x != nil && y != nil
        }
        return !value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    /// 实际发给 Appium 的 locator value。
    var appiumValue: String? {
        switch strategy {
        case .label:
            let escaped = value
                .replacingOccurrences(of: "\\", with: "\\\\")
                .replacingOccurrences(of: "\"", with: "\\\"")
            return "label == \"\(escaped)\""
        case .point:
            return nil
        default:
            return value
        }
    }

    var summary: String {
        if strategy == .point {
            return "坐标 (\(x ?? 0), \(y ?? 0))"
        }
        return "\(strategy.displayName): \(value)"
    }

    // MARK: - Codable（老 JSON 没有 locator 字段，必须容错）

    private enum CodingKeys: String, CodingKey {
        case strategy, value, index, timeout, x, y
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        strategy = try container.decodeIfPresent(LocatorStrategy.self, forKey: .strategy) ?? .accessibilityId
        value = try container.decodeIfPresent(String.self, forKey: .value) ?? ""
        index = try container.decodeIfPresent(Int.self, forKey: .index)
        timeout = try container.decodeIfPresent(Double.self, forKey: .timeout) ?? 5.0
        x = try container.decodeIfPresent(Int.self, forKey: .x)
        y = try container.decodeIfPresent(Int.self, forKey: .y)
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(strategy, forKey: .strategy)
        try container.encode(value, forKey: .value)
        try container.encodeIfPresent(index, forKey: .index)
        try container.encode(timeout, forKey: .timeout)
        try container.encodeIfPresent(x, forKey: .x)
        try container.encodeIfPresent(y, forKey: .y)
    }
}
