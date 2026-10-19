import DeckConfig
import DeckRender
import SwiftUI

struct EditorView: View {
    @Bindable var model: EditorModel
    let actions: EditorActions

    var body: some View {
        Group {
            if let errors = model.unreadable {
                UnreadableView(errors: errors, actions: actions)
            } else {
                NavigationSplitView {
                    PageSidebar(model: model)
                        .navigationSplitViewColumnWidth(min: 180, ideal: 200)
                } detail: {
                    VStack(spacing: 0) {
                        if let diskErrors = model.diskErrors {
                            Banner(text: "The config file on disk has errors. The editor keeps your draft.", errors: diskErrors)
                        }
                        if model.showsSettings {
                            SettingsView(model: model)
                        } else if let page = model.selectedPage, model.draft.page(named: page) != nil {
                            PageEditor(model: model, page: page)
                        } else {
                            ContentUnavailableView("No Page", systemImage: "square.grid.3x2", description: Text("Add a page in the sidebar."))
                        }
                    }
                }
            }
        }
        .toolbar {
            ToolbarItemGroup(placement: .primaryAction) {
                Button("Revert", action: actions.revert)
                    .disabled(!model.isDirty || model.unreadable != nil)
                    .help("Discard unsaved changes and reload config.yaml")
                Button("Save", action: actions.save)
                    .keyboardShortcut("s")
                    .disabled(!model.isDirty || !model.canSave)
                    .help(model.canSave ? "Write config.yaml" : "Fix the errors to save")
            }
        }
        .alert("The config file changed on disk", isPresented: Binding(
            get: { model.pendingDiskDocument != nil },
            set: { _ in }
        )) {
            Button("Reload from Disk") { model.resolveDiskChange(reload: true) }
            Button("Keep My Changes", role: .cancel) { model.resolveDiskChange(reload: false) }
        } message: {
            Text("You have unsaved changes. Reloading discards them.")
        }
    }
}

// MARK: - Sidebar

private enum SidebarItem: Hashable {
    case page(String)
    case settings
}

private struct PageSidebar: View {
    @Bindable var model: EditorModel
    @State private var naming: NamingRequest?
    @State private var newName = ""
    @State private var message: String?

    private struct NamingRequest: Identifiable {
        var id: String { renaming ?? "" }
        /// nil adds a page.
        var renaming: String?
    }

    var body: some View {
        List(selection: selection) {
            Section("Pages") {
                ForEach(model.draft.pages, id: \.name) { page in
                    HStack {
                        Text(page.name)
                        Spacer()
                        if page.name == model.draft.defaultPage {
                            Image(systemName: "house").foregroundStyle(.secondary).help("Default page")
                        }
                        if model.errors.contains(where: { $0.page == page.name }) {
                            Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(.red)
                        }
                    }
                    .tag(SidebarItem.page(page.name))
                    .contextMenu {
                        Button("Rename…") { startNaming(renaming: page.name) }
                        Button("Delete", role: .destructive) { delete(page.name) }
                    }
                }
            }
            Section {
                Label("Settings", systemImage: "gearshape")
                    .tag(SidebarItem.settings)
                    .badge(model.settingsErrors.count)
            }
        }
        .safeAreaInset(edge: .bottom) {
            HStack {
                Button { startNaming(renaming: nil) } label: { Image(systemName: "plus") }
                    .help("Add a page")
                Button {
                    if let page = model.selectedPage { delete(page) }
                } label: { Image(systemName: "minus") }
                    .help("Delete the selected page")
                    .disabled(model.selectedPage == nil || model.showsSettings)
                Spacer()
            }
            .buttonStyle(.borderless)
            .padding(8)
        }
        .alert(naming?.renaming == nil ? "Add Page" : "Rename Page", isPresented: Binding(
            get: { naming != nil },
            set: { if !$0 { naming = nil } }
        )) {
            TextField("Page name", text: $newName)
            Button(naming?.renaming == nil ? "Add" : "Rename") { finishNaming() }
            Button("Cancel", role: .cancel) {}
        }
        .alert(message ?? "", isPresented: Binding(get: { message != nil }, set: { if !$0 { message = nil } })) {
            Button("OK", role: .cancel) {}
        }
    }

    private var selection: Binding<SidebarItem?> {
        Binding(
            get: { model.showsSettings ? .settings : model.selectedPage.map(SidebarItem.page) },
            set: { item in
                switch item {
                case .settings:
                    model.showsSettings = true
                case let .page(name):
                    model.showsSettings = false
                    model.selectedPage = name
                case nil:
                    break
                }
            }
        )
    }

    private func startNaming(renaming: String?) {
        newName = renaming ?? ""
        naming = NamingRequest(renaming: renaming)
    }

    private func finishNaming() {
        guard let request = naming else { return }
        naming = nil
        do {
            if let old = request.renaming {
                try model.renamePage(old, to: newName)
            } else {
                try model.addPage(named: newName)
                model.showsSettings = false
            }
        } catch {
            message = switch error {
            case .empty: "A page needs a name."
            case .reserved: "“back” is reserved for the page action that returns to the previous page."
            case let .taken(name): "A page named “\(name)” already exists."
            }
        }
    }

    private func delete(_ page: String) {
        let references = model.deletePage(page)
        guard !references.isEmpty else { return }
        message = "“\(page)” is still used by: " + references.map(\.description).joined(separator: "; ") + "."
    }
}

// MARK: - Page

private struct PageEditor: View {
    @Bindable var model: EditorModel
    let page: String

    var body: some View {
        HStack(spacing: 0) {
            VStack(spacing: 16) {
                KeyGrid(model: model, page: page)
                Text("Click a key, or press it on the deck, to edit it.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                ErrorList(errors: model.errors(page: page))
            }
            .padding(24)
            .frame(maxWidth: .infinity, maxHeight: .infinity)

            Divider()

            Group {
                if let index = model.selectedKey {
                    KeyInspector(model: model, page: page, index: index)
                } else {
                    ContentUnavailableView("No Key Selected", systemImage: "square.dashed")
                }
            }
            .frame(width: 340)
        }
    }
}

private struct KeyGrid: View {
    let model: EditorModel
    let page: String

    var body: some View {
        Grid(horizontalSpacing: 12, verticalSpacing: 12) {
            ForEach(0 ..< 3, id: \.self) { row in
                GridRow {
                    ForEach(0 ..< 5, id: \.self) { column in
                        cell(row * 5 + column)
                    }
                }
            }
        }
        .padding(16)
        .background(RoundedRectangle(cornerRadius: 18).fill(Color(white: 0.12)))
    }

    private func cell(_ index: Int) -> some View {
        let selected = model.selectedKey == index
        let hasErrors = !model.errors(page: page, key: index).isEmpty
        return Image(decorative: KeyRenderer.preview(appearance(index)), scale: 1)
            .resizable()
            .interpolation(.high)
            .frame(width: 80, height: 80)
            .clipShape(RoundedRectangle(cornerRadius: 10))
            .overlay {
                RoundedRectangle(cornerRadius: 10)
                    .strokeBorder(hasErrors ? Color.red : selected ? Color.accentColor : Color.white.opacity(0.15),
                                  lineWidth: hasErrors || selected ? 3 : 1)
            }
            .overlay(alignment: .topLeading) {
                Text("\(index)").font(.caption2.monospacedDigit()).foregroundStyle(.white.opacity(0.5)).padding(5)
            }
            .contentShape(Rectangle())
            .onTapGesture { model.selectedKey = index }
            .accessibilityLabel("Key \(index)")
            .accessibilityAddTraits(selected ? [.isButton, .isSelected] : .isButton)
    }

    /// From the last valid draft, so the grid matches what the deck shows.
    private func appearance(_ index: Int) -> KeyAppearance {
        guard let key = model.lastValid?.pages[page]?.keys[index] else { return .blank }
        let label = key.label ?? (key.dynamic != nil ? "…" : nil)
        return KeyAppearance(background: key.background ?? .black, icon: key.icon, label: label)
    }
}

// MARK: - Shared pieces

struct ErrorList: View {
    let errors: [ConfigError]

    var body: some View {
        if !errors.isEmpty {
            VStack(alignment: .leading, spacing: 4) {
                ForEach(Array(errors.enumerated()), id: \.offset) { _, error in
                    Label(error.message, systemImage: "exclamationmark.circle.fill")
                        .foregroundStyle(.red)
                        .font(.callout)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}

private struct Banner: View {
    let text: String
    let errors: [ConfigError]

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Label(text, systemImage: "exclamationmark.triangle.fill").font(.callout.bold())
            ForEach(Array(errors.prefix(3).enumerated()), id: \.offset) { _, error in
                Text(error.description).font(.caption)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(10)
        .background(Color.yellow.opacity(0.2))
    }
}

private struct UnreadableView: View {
    let errors: [ConfigError]
    let actions: EditorActions

    var body: some View {
        VStack(spacing: 16) {
            Image(systemName: "doc.badge.ellipsis").font(.system(size: 40)).foregroundStyle(.secondary)
            Text("The config file cannot be opened in the editor").font(.title3)
            Text("Fix these problems in a text editor. The editor reloads when the file is saved.")
                .foregroundStyle(.secondary)
            VStack(alignment: .leading, spacing: 4) {
                ForEach(Array(errors.enumerated()), id: \.offset) { _, error in
                    Text(error.description).font(.callout.monospaced())
                }
            }
            .padding()
            .background(RoundedRectangle(cornerRadius: 8).fill(.quaternary))
            HStack {
                Button("Open Config", action: actions.openConfigFile)
                Button("Try Again", action: actions.revert)
            }
        }
        .padding(40)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
