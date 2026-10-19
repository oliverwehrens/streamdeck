import SwiftUI

/// Point-and-click SF Symbol chooser: search, category filter, and a grid of symbols.
struct SymbolPicker: View {
    /// The current symbol name, highlighted in the grid.
    let current: String
    let choose: (String) -> Void

    @State private var query = ""
    @State private var category: String?

    var body: some View {
        if let catalog = SymbolCatalog.system {
            content(catalog)
        } else {
            ContentUnavailableView(
                "Symbol list unavailable",
                systemImage: "exclamationmark.triangle",
                description: Text("This version of macOS doesn't provide the SF Symbols list. Type the symbol name instead.")
            )
            .frame(width: 360, height: 200)
        }
    }

    private func content(_ catalog: SymbolCatalog) -> some View {
        let symbols = catalog.symbols(matching: query, category: category)
        let current = catalog.currentName(current)
        return VStack(spacing: 8) {
            HStack {
                TextField("Search", text: $query, prompt: Text("Search symbols, e.g. mic or arrow"))
                    .textFieldStyle(.roundedBorder)
                Picker("Category", selection: $category) {
                    Label("All", systemImage: "square.grid.2x2").tag(String?.none)
                    Divider()
                    ForEach(catalog.categories, id: \.key) { category in
                        Label(category.title, systemImage: category.icon).tag(Optional(category.key))
                    }
                }
                .labelsHidden()
                .fixedSize()
            }
            ScrollView {
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 44), spacing: 4)], spacing: 4) {
                    ForEach(symbols, id: \.self) { name in
                        Button { choose(name) } label: {
                            Image(systemName: name)
                                .font(.title2)
                                .frame(width: 44, height: 40)
                                .background(RoundedRectangle(cornerRadius: 6).fill(name == current ? Color.accentColor.opacity(0.3) : .clear))
                                .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .help(name)
                        .accessibilityLabel(name)
                    }
                }
                .padding(4)
            }
            Text(symbols.isEmpty ? "No matching symbols" : "\(symbols.count) symbols · hover for the name")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(12)
        .frame(width: 480, height: 440)
    }
}
