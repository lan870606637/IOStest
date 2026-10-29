import Foundation
import CoreGraphics

// MARK: - Appium HTTP 客户端
/// 只负责 Appium 的 W3C WebDriver 协议，不关心设备/会话生命周期。
final class AppiumClient {
    let baseURL: URL

    private let session: URLSession
    private let logger = Logger.shared
    private static let w3cElementKey = "element-6066-11e4-a52e-4f735466cecf"

    init(baseURL: URL, requestTimeout: TimeInterval = 180) {
        self.baseURL = baseURL
        let configuration = URLSessionConfiguration.ephemeral
        configuration.timeoutIntervalForRequest = requestTimeout
        configuration.timeoutIntervalForResource = requestTimeout
        configuration.httpMaximumConnectionsPerHost = 4
        self.session = URLSession(configuration: configuration)
    }

    // MARK: - 基础请求

    private func request(_ method: String,
                         _ path: String,
                         body: [String: Any]? = nil) async throws -> Any {
        guard let url = URL(string: path, relativeTo: baseURL) else {
            throw AutomationError.invalidResponse("非法路径 \(path)")
        }

        var request = URLRequest(url: url)
        request.httpMethod = method
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        if let body {
            request.httpBody = try JSONSerialization.data(withJSONObject: body)
        }

        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await session.data(for: request)
        } catch {
            throw AutomationError.commandFailed("\(method) \(path) 失败：\(error.localizedDescription)")
        }

        guard let http = response as? HTTPURLResponse else {
            throw AutomationError.invalidResponse("\(method) \(path) 没有 HTTP 响应")
        }

        let json = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any]
        let value = json?["value"]

        if http.statusCode >= 400 {
            let message = (value as? [String: Any])?["message"] as? String
                ?? "HTTP \(http.statusCode) \(method) \(path)"
            let lowered = message.lowercased()
            if lowered.contains("invalid session id") {
                throw AutomationError.sessionUnavailable(message)
            }
            if http.statusCode == 404
                || lowered.contains("no such element")
                || lowered.contains("could not be located") {
                throw AutomationError.elementNotFound(message)
            }
            throw AutomationError.commandFailed(message)
        }

        return value ?? NSNull()
    }

    private static func element(from value: Any) -> ElementHandle? {
        guard let dictionary = value as? [String: Any] else { return nil }
        if let id = dictionary[w3cElementKey] as? String {
            return ElementHandle(id: id)
        }
        if let id = dictionary["ELEMENT"] as? String {
            return ElementHandle(id: id)
        }
        return nil
    }

    // MARK: - 服务

    func status() async throws -> Bool {
        let value = try await request("GET", "/status")
        return (value as? [String: Any])?["ready"] as? Bool ?? false
    }

    // MARK: - 会话

    func createSession(_ capabilities: [String: Any]) async throws -> String {
        let body: [String: Any] = ["capabilities": ["alwaysMatch": capabilities]]
        let value = try await request("POST", "/session", body: body)
        guard let dictionary = value as? [String: Any],
              let sessionId = dictionary["sessionId"] as? String else {
            throw AutomationError.invalidResponse("创建会话没有返回 sessionId")
        }
        logger.info("Appium 会话已创建: \(sessionId)")
        return sessionId
    }

    func deleteSession(_ sessionId: String) async {
        do {
            _ = try await request("DELETE", "/session/\(sessionId)")
            logger.info("Appium 会话已关闭: \(sessionId)")
        } catch {
            logger.warning("关闭 Appium 会话失败 (\(sessionId)): \(error.localizedDescription)")
        }
    }

    // MARK: - 页面

    func source(sessionId: String) async throws -> String {
        let value = try await request("GET", "/session/\(sessionId)/source")
        guard let source = value as? String else {
            throw AutomationError.invalidResponse("source 不是字符串")
        }
        return source
    }

    func screenshot(sessionId: String) async throws -> Data {
        let value = try await request("GET", "/session/\(sessionId)/screenshot")
        guard let base64 = value as? String, let data = Data(base64Encoded: base64) else {
            throw AutomationError.invalidResponse("screenshot 不是合法的 base64")
        }
        return data
    }

    func execute(sessionId: String, script: String, args: [Any] = []) async throws -> Any {
        try await request("POST", "/session/\(sessionId)/execute/sync",
                          body: ["script": script, "args": args])
    }

    /// 向当前焦点控件输入文字（W3C keys）。
    func sendKeys(sessionId: String, text: String) async throws {
        _ = try await request("POST", "/session/\(sessionId)/keys",
                              body: ["value": [text]])
    }

    // MARK: - 元素

    func findElement(sessionId: String,
                     using: String,
                     value: String,
                     index: Int? = nil) async throws -> ElementHandle? {
        if let index {
            let result = try await request("POST", "/session/\(sessionId)/elements",
                                           body: ["using": using, "value": value])
            guard let matches = result as? [[String: Any]], index >= 0, index < matches.count else {
                return nil
            }
            return Self.element(from: matches[index])
        }

        do {
            let result = try await request("POST", "/session/\(sessionId)/element",
                                           body: ["using": using, "value": value])
            return Self.element(from: result)
        } catch AutomationError.elementNotFound {
            return nil
        }
    }

    func click(sessionId: String, element: ElementHandle) async throws {
        _ = try await request("POST", "/session/\(sessionId)/element/\(element.id)/click")
    }

    func rect(sessionId: String, element: ElementHandle) async throws -> CGRect {
        let value = try await request("GET", "/session/\(sessionId)/element/\(element.id)/rect")
        guard let dictionary = value as? [String: Any] else {
            throw AutomationError.invalidResponse("rect 不是对象")
        }
        func number(_ key: String) -> CGFloat {
            if let number = dictionary[key] as? NSNumber {
                return CGFloat(number.doubleValue)
            }
            if let double = dictionary[key] as? Double {
                return CGFloat(double)
            }
            return 0
        }
        return CGRect(x: number("x"), y: number("y"),
                      width: number("width"), height: number("height"))
    }
}
