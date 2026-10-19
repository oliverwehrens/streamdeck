import AppKit
import DeckConfig
import SwiftUI
import UniformTypeIdentifiers

/// Brightness, default page and per-app pages.
struct SettingsView: View {
    @Bindable var model: EditorModel

    var body: some View {
        Form {
            Section("Deck") {
                LabeledContent("Brightness") {
                    HStack {
                        Slider(value: brightness, in: 0 ... 100, step: 1)
                        Text("\(Int(brightness.wrappedValue))%").monospacedDigit().frame(width: 44, alignment: .trailing)
                    }
                }
                Picker("Default page", selection: $model.draft.defaultPage) {
                    ForEach(model.draft.pages, id: \.name) { Text($0.name).tag($0.name) }
                    if model.draft.page(named: model.draft.defaultPage) == nil {
                        Text("\(model.draft.defaultPage) (missing)").tag(model.draft.defaultPage)
                    }
                }
            }

            Section {
                ForEach(model.draft.appPages.indices, id: \.self) { index in
                    AppPageRow(entry: appPage(index), pages: model.draft.pages.map(\.name)) {
                        model.draft.appPages.remove(at: index)
                    }
                }
                AddAppMenu { bundleID in
                    let page = model.selectedPage ?? model.draft.defaultPage
                    model.draft.appPages.append(AppPageDocument(bundleID: bundleID, page: page))
                }
            } header: {
                Text("App pages")
            } footer: {
                Text("When an app comes to the front, the deck shows its page. Other apps show the default page.")
                    .font(.caption).foregroundStyle(.secondary)
            }

            if !model.settingsErrors.isEmpty {
                Section { ErrorList(errors: model.settingsErrors) }
            }
        }
        .formStyle(.grouped)
    }

    /// Bounds-checked, because a removed row can still be read once while SwiftUI updates.
    private func appPage(_ index: Int) -> Binding<AppPageDocument> {
        Binding(
            get: { model.draft.appPages.indices.contains(index) ? model.draft.appPages[index] : AppPageDocument(bundleID: "", page: "") },
            set: { if model.draft.appPages.indices.contains(index) { model.draft.appPages[index] = $0 } }
        )
    }

    /// Omitted brightness means the default; a value that isn't a number reads as the default too.
    private var brightness: Binding<Double> {
        Binding(
            get: { Double(model.draft.brightness.flatMap { Int($0) } ?? DeckConfig.defaultBrightness) },
            set: { model.draft.brightness = String(Int($0)) }
        )
    }
}

private struct AppPageRow: View {
    @Binding var entry: AppPageDocument
    let pages: [String]
    let remove: () -> Void

    var body: some View {
        HStack {
            if let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: entry.bundleID) {
                Image(nsImage: NSWorkspace.shared.icon(forFile: url.path)).resizable().frame(width: 20, height: 20)
            }
            TextField("Bundle ID", text: $entry.bundleID).labelsHidden()
            Picker("Page", selection: $entry.page) {
                ForEach(pages, id: \.self) { Text($0).tag($0) }
                if !pages.contains(entry.page) { Text("\(entry.page) (missing)").tag(entry.page) }
            }
            .labelsHidden()
            .frame(width: 140)
            Button(role: .destructive, action: remove) { Image(systemName: "minus.circle") }
                .buttonStyle(.borderless)
                .help("Remove")
        }
    }
}

/// Adds an app by picking a running app or an application bundle.
private struct AddAppMenu: View {
    let add: (String) -> Void

    var body: some View {
        Menu("Add App") {
            ForEach(runningApps, id: \.bundleID) { app in
                Button(app.name) { add(app.bundleID) }
            }
            Divider()
            Button("Choose App…") {
                let panel = NSOpenPanel()
                panel.allowedContentTypes = [.application]
                panel.directoryURL = URL(fileURLWithPath: "/Applications")
                if panel.runModal() == .OK, let url = panel.url, let bundleID = Bundle(url: url)?.bundleIdentifier {
                    add(bundleID)
                }
            }
        }
    }

    private var runningApps: [(name: String, bundleID: String)] {
        NSWorkspace.shared.runningApplications
            .filter { $0.activationPolicy == .regular && $0.bundleIdentifier != Bundle.main.bundleIdentifier }
            .compactMap { app in app.bundleIdentifier.map { (app.localizedName ?? $0, $0) } }
            .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }
}
