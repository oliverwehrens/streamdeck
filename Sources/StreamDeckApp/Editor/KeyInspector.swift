import AppKit
import DeckConfig
import SwiftUI
import UniformTypeIdentifiers

/// Edits one key of the selected page. Every change goes straight into the draft.
struct KeyInspector: View {
    let model: EditorModel
    let page: String
    let index: Int

    private var key: Binding<KeyDocument> {
        Binding(get: { model.key(index) ?? KeyDocument() }, set: { model.setKey(index, $0) })
    }

    var body: some View {
        Form {
            Section {
                IconEditor(icon: key.icon, configDirectory: model.configDirectory)
                TextField("Label", text: optionalText(key.label), prompt: Text("None"))
                BackgroundEditor(background: key.background)
            } header: {
                Text("Key \(index)").font(.headline)
            }
            Section("Action") {
                ActionEditor(action: key.action, pages: model.draft.pages.map(\.name), configDirectory: model.configDirectory)
            }
            Section("Dynamic label") {
                DynamicEditor(dynamic: key.dynamic)
            }
            let errors = model.errors(page: page, key: index)
            if !errors.isEmpty {
                Section { ErrorList(errors: errors) }
            }
            Section {
                Button("Clear Key", role: .destructive) { model.setKey(index, nil) }
                    .disabled(model.key(index) == nil)
            }
        }
        .formStyle(.grouped)
    }
}

/// Empty text means the field is omitted.
private func optionalText(_ value: Binding<String?>) -> Binding<String> {
    Binding(get: { value.wrappedValue ?? "" }, set: { value.wrappedValue = $0.isEmpty ? nil : $0 })
}

// MARK: - Icon

private struct IconEditor: View {
    @Binding var icon: String?
    let configDirectory: URL
    @State private var pickingSymbol = false

    private enum Kind: String, CaseIterable {
        case none = "None", symbol = "SF Symbol", file = "Image"
    }

    private var kind: Binding<Kind> {
        Binding(
            get: { icon == nil ? .none : icon!.hasPrefix("sf:") ? .symbol : .file },
            set: { kind in
                switch kind {
                case .none: icon = nil
                case .symbol: icon = "sf:"
                case .file: icon = ""
                }
            }
        )
    }

    var body: some View {
        Picker("Icon", selection: kind) {
            ForEach(Kind.allCases, id: \.self) { Text($0.rawValue) }
        }
        switch kind.wrappedValue {
        case .none:
            EmptyView()
        case .symbol:
            let name = String((icon ?? "sf:").dropFirst(3))
            HStack {
                TextField("Symbol", text: Binding(get: { name }, set: { icon = "sf:" + $0 }), prompt: Text("e.g. mic.slash.fill"))
                if !name.isEmpty {
                    if NSImage(systemSymbolName: name, accessibilityDescription: nil) != nil {
                        Image(systemName: name).frame(width: 24)
                    } else {
                        Image(systemName: "questionmark.square.dashed").foregroundStyle(.red).frame(width: 24)
                            .help("Unknown SF Symbol")
                    }
                }
                Button("Choose…") { pickingSymbol = true }
                    .popover(isPresented: $pickingSymbol, arrowEdge: .leading) {
                        SymbolPicker(current: name) { chosen in
                            icon = "sf:" + chosen
                            pickingSymbol = false
                        }
                    }
            }
        case .file:
            HStack {
                TextField("File", text: Binding(get: { icon ?? "" }, set: { icon = $0 }), prompt: Text("icons/name.png"))
                Button("Choose…") {
                    if let path = choosePath(types: [.png, .jpeg], configDirectory: configDirectory) { icon = path }
                }
            }
        }
    }
}

/// Picks a file. Paths inside the config directory come back relative to it, others with `~` abbreviated.
@MainActor
func choosePath(types: [UTType]? = nil, directories: Bool = false, configDirectory: URL) -> String? {
    let panel = NSOpenPanel()
    panel.canChooseDirectories = directories
    panel.treatsFilePackagesAsDirectories = false
    if let types { panel.allowedContentTypes = types }
    panel.directoryURL = configDirectory
    guard panel.runModal() == .OK, let url = panel.url else { return nil }
    let path = url.standardizedFileURL.path
    let base = configDirectory.standardizedFileURL.path + "/"
    return path.hasPrefix(base) ? String(path.dropFirst(base.count)) : (path as NSString).abbreviatingWithTildeInPath
}

// MARK: - Background

private struct BackgroundEditor: View {
    @Binding var background: String?

    var body: some View {
        Toggle("Background color", isOn: Binding(
            get: { background != nil },
            set: { background = $0 ? "#000000" : nil }
        ))
        if let text = background {
            HStack {
                TextField("Hex", text: Binding(get: { text }, set: { background = $0 }), prompt: Text("#RRGGBB"))
                    .font(.body.monospaced())
                ColorPicker("Color", selection: color, supportsOpacity: false).labelsHidden()
            }
        }
    }

    private var color: Binding<Color> {
        Binding(
            get: {
                let hex = background.flatMap(HexColor.init(hex:)) ?? .black
                return Color(.sRGB, red: Double(hex.red) / 255, green: Double(hex.green) / 255, blue: Double(hex.blue) / 255)
            },
            set: { color in
                guard let rgb = NSColor(color).usingColorSpace(.sRGB) else { return }
                func byte(_ component: CGFloat) -> Int { Int((min(max(component, 0), 1) * 255).rounded()) }
                background = String(format: "#%02X%02X%02X", byte(rgb.redComponent), byte(rgb.greenComponent), byte(rgb.blueComponent))
            }
        )
    }
}

// MARK: - Action

private struct ActionEditor: View {
    @Binding var action: ActionDocument?
    let pages: [String]
    let configDirectory: URL

    private static let kindNames: [ActionDocument.Kind: String] = [
        .run: "Run command", .open: "Open", .keys: "Keystroke", .media: "Media key", .page: "Go to page",
    ]

    private var kind: Binding<ActionDocument.Kind?> {
        Binding(
            get: { action?.kind },
            set: { kind in
                guard let kind else { action = nil; return }
                guard kind != action?.kind else { return }
                let value = switch kind {
                case .media: MediaKey.playpause.rawValue
                case .page: pages.first ?? "back"
                default: ""
                }
                action = ActionDocument(kind, value)
            }
        )
    }

    private var value: Binding<String> {
        Binding(get: { action?.value ?? "" }, set: { action?.value = $0 })
    }

    var body: some View {
        Picker("Type", selection: kind) {
            Text("None").tag(ActionDocument.Kind?.none)
            ForEach(ActionDocument.Kind.allCases, id: \.self) { kind in
                Text(Self.kindNames[kind]!).tag(Optional(kind))
            }
        }
        switch action?.kind {
        case nil:
            EmptyView()
        case .run:
            TextField("Command", text: value, prompt: Text("say hello"))
                .font(.body.monospaced())
            Text("Runs in your login shell. A non-zero exit shows up in the menu.")
                .font(.caption).foregroundStyle(.secondary)
        case .open:
            HStack {
                TextField("Target", text: value, prompt: Text("URL, file, folder or app"))
                Button("Choose…") {
                    if let path = choosePath(directories: true, configDirectory: configDirectory) { value.wrappedValue = path }
                }
            }
        case .keys:
            TextField("Keys", text: value, prompt: Text("cmd+shift+m"))
                .font(.body.monospaced())
            Text("Modifiers cmd, shift, alt, ctrl, fn plus one key. Needs Accessibility permission.")
                .font(.caption).foregroundStyle(.secondary)
        case .media:
            Picker("Media key", selection: value) {
                ForEach(MediaKey.allCases, id: \.rawValue) { Text($0.rawValue).tag($0.rawValue) }
                if MediaKey(rawValue: value.wrappedValue) == nil { Text(value.wrappedValue).tag(value.wrappedValue) }
            }
        case .page:
            Picker("Page", selection: value) {
                ForEach(pages, id: \.self) { Text($0).tag($0) }
                Text("Back (previous page)").tag("back")
                if !pages.contains(value.wrappedValue), value.wrappedValue != "back" {
                    Text("\(value.wrappedValue) (missing)").tag(value.wrappedValue)
                }
            }
        }
    }
}

// MARK: - Dynamic

private struct DynamicEditor: View {
    @Binding var dynamic: DynamicDocument?

    var body: some View {
        Toggle("Show command output as label", isOn: Binding(
            get: { dynamic != nil },
            set: { dynamic = $0 ? DynamicDocument(run: "", every: "30s") : nil }
        ))
        if dynamic != nil {
            TextField("Command", text: Binding(get: { dynamic?.run ?? "" }, set: { dynamic?.run = $0 }), prompt: Text("date +%H:%M"))
                .font(.body.monospaced())
            TextField("Every", text: Binding(get: { dynamic?.every ?? "" }, set: { dynamic?.every = $0 }), prompt: Text("30s"))
            Text("Units ms, s, m, h. Minimum 1s. Runs only while the page is shown.")
                .font(.caption).foregroundStyle(.secondary)
        }
    }
}
