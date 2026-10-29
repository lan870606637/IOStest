import SwiftUI

// MARK: - 控件树节点
final class AXNode: Identifiable {
    let id = UUID()
    let type: String
    let name: String
    let label: String
    let value: String
    let rect: CGRect
    let enabled: Bool
    var depth: Int
    var children: [AXNode] = []

    init(attributes: [String: String], depth: Int) {
        type = attributes["type"] ?? ""
        name = attributes["name"] ?? ""
        label = attributes["label"] ?? ""
        value = attributes["value"] ?? ""
        enabled = (attributes["enabled"] ?? "true") == "true"
        self.depth = depth
        rect = CGRect(
            x: Double(attributes["x"] ?? "") ?? 0,
            y: Double(attributes["y"] ?? "") ?? 0,
            width: Double(attributes["width"] ?? "") ?? 0,
            height: Double(attributes["height"] ?? "") ?? 0
        )
    }

    var displayText: String {
        if !label.isEmpty { return label }
        if !name.isEmpty { return name }
        if !value.isEmpty { return value }
        return type.replacingOccurrences(of: "XCUIElementType", with: "")
    }
}

// MARK: - XML 解析
final class AXTreeParser: NSObject, XMLParserDelegate {
    static func parse(_ xml: String) -> [AXNode] {
        guard let data = xml.data(using: .utf8) else { return [] }
        let parser = XMLParser(data: data)
        let delegate = AXTreeParser()
        parser.delegate = delegate
        parser.parse()
        return delegate.roots
    }

    private var roots: [AXNode] = []
    private var stack: [AXNode] = []

    func parser(_ parser: XMLParser,
                didStartElement elementName: String,
                namespaceURI: String?,
                qualifiedName qName: String?,
                attributes attributeDict: [String: String] = [:]) {
        let node = AXNode(attributes: attributeDict, depth: stack.count)
        if let parent = stack.last {
            parent.children.append(node)
        } else {
            roots.append(node)
        }
        stack.append(node)
    }

    func parser(_ parser: XMLParser,
                didEndElement elementName: String,
                namespaceURI: String?,
                qualifiedName qName: String?) {
        if !stack.isEmpty {
            stack.removeLast()
        }
    }
}

// MARK: - 控件检查器
struct ElementInspectorView: View {
    let deviceUDID: String
    let onPick: (Locator, CGRect) -> Void

    @Environment(\.dismiss) private var dismiss

    @State private var nodes: [AXNode] = []
    @State private var selectedID: UUID?
    @State private var search = ""
    @State private var isLoading = false
    @State private var errorMessage: String?
    @State private var showSource = false
    @State private var source = ""

    private let backend = AppiumBackend()

    private var flattened: [AXNode] {
        var result: [AXNode] = []
        func walk(_ node: AXNode) {
            if matches(node) { result.append(node) }
            for child in node.children { walk(child) }
        }
        nodes.forEach(walk)
        return result
    }

    private var selectedNode: AXNode? {
        guard let selectedID else { return nil }
        return flattened.first { $0.id == selectedID }
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 12) {
                Text("控件检查器")
                    .font(.headline)
                Text(deviceUDID)
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .lineLimit(1)
                Spacer()
                Button("刷新") { load() }
                Button("关闭") { dismiss() }
            }
            .padding()

            Divider()

            HStack(spacing: 12) {
                TextField("搜索 label / name / type", text: $search)
                    .textFieldStyle(.roundedBorder)
                Toggle("XML", isOn: $showSource)
                    .toggleStyle(.switch)
            }
            .padding(.horizontal)
            .padding(.vertical, 8)

            if isLoading {
                Spacer()
                ProgressView("读取控件树（首次可能需要 30 秒）...")
                Spacer()
            } else if let errorMessage {
                Spacer()
                Text(errorMessage)
                    .foregroundColor(.red)
                    .multilineTextAlignment(.center)
                    .padding()
                Spacer()
            } else if showSource {
                ScrollView {
                    Text(source)
                        .font(.system(.caption, design: .monospaced))
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding()
                }
            } else {
                List(flattened, selection: $selectedID) { node in
                    HStack(spacing: 6) {
                        Image(systemName: icon(for: node.type))
                            .foregroundColor(.secondary)
                            .frame(width: 16)
                        Text(node.displayText)
                            .lineLimit(1)
                        Spacer()
                        Text(node.type.replacingOccurrences(of: "XCUIElementType", with: ""))
                            .font(.caption2)
                            .foregroundColor(.secondary)
                        Text("\(Int(node.rect.midX)),\(Int(node.rect.midY))")
                            .font(.caption2.monospacedDigit())
                            .foregroundColor(.secondary)
                    }
                    .padding(.leading, CGFloat(node.depth) * 8)
                    .tag(node.id)
                }
            }

            Divider()

            HStack {
                if let selectedNode, let locator = makeLocator(for: selectedNode) {
                    Text(locator.summary)
                        .font(.caption)
                        .lineLimit(1)
                } else {
                    Text("选择一个控件")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                Spacer()
                Button("使用此控件") {
                    guard let selectedNode, let locator = makeLocator(for: selectedNode) else { return }
                    onPick(locator, selectedNode.rect)
                    dismiss()
                }
                .buttonStyle(.borderedProminent)
                .disabled(selectedNode == nil)
            }
            .padding()
        }
        .frame(width: 720, height: 560)
        .onAppear(perform: load)
    }

    // MARK: - 加载

    private func load() {
        isLoading = true
        errorMessage = nil
        Task {
            do {
                try await backend.ensureSession(udid: deviceUDID, bundleId: nil, platformVersion: nil)
                let xml = try await backend.source(udid: deviceUDID)
                let parsed = AXTreeParser.parse(xml)
                await MainActor.run {
                    source = xml
                    nodes = parsed
                    selectedID = parsed.first?.id
                    isLoading = false
                }
            } catch {
                await MainActor.run {
                    errorMessage = error.localizedDescription
                    isLoading = false
                }
            }
        }
    }

    // MARK: - 辅助

    private func matches(_ node: AXNode) -> Bool {
        guard !search.isEmpty else { return true }
        let query = search.lowercased()
        return node.name.lowercased().contains(query)
            || node.label.lowercased().contains(query)
            || node.type.lowercased().contains(query)
    }

    private func icon(for type: String) -> String {
        if type.contains("Button") { return "hand.tap" }
        if type.contains("TextField") || type.contains("TextView") { return "text.cursor" }
        if type.contains("Switch") { return "switch.2" }
        if type.contains("Cell") { return "rectangle" }
        if type.contains("Image") { return "photo" }
        return "square"
    }

    private func makeLocator(for node: AXNode) -> Locator? {
        if !node.name.isEmpty {
            return Locator(strategy: .accessibilityId, value: node.name)
        }
        if !node.label.isEmpty {
            return Locator(strategy: .label, value: node.label)
        }
        if !node.type.isEmpty {
            return Locator(strategy: .predicate, value: "type == \"\(node.type)\"")
        }
        return nil
    }
}
