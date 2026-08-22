import SwiftUI

@main
struct ReferenceApp: App {
    @State private var model = AppModel()

    var body: some Scene {
        WindowGroup("Reference Engine") {
            ContentView()
                .environment(model)
                .frame(minWidth: 980, minHeight: 640)
                .task { model.load() }
        }
        .windowToolbarStyle(.unified)
    }
}

struct ContentView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        NavigationSplitView {
            CatalogSidebar()
        } detail: {
            if let error = model.loadError {
                ContentUnavailableView(
                    "No corpus found",
                    systemImage: "questionmark.folder",
                    description: Text(error)
                )
            } else if let catalog = model.selectedCatalog {
                CatalogDetail(catalog: catalog)
            } else {
                ContentUnavailableView("Select a catalog", systemImage: "square.grid.2x2")
            }
        }
    }
}

struct CatalogSidebar: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        List(selection: Binding(
            get: { model.selectedCatalog },
            set: { model.selectedCatalog = $0 }
        )) {
            ForEach(model.catalogs) { catalog in
                NavigationLink(value: catalog) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(catalog.title)
                            .font(.body)
                        Text("\(catalog.count) records · \(catalog.completeRecordCount) complete")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    .padding(.vertical, 2)
                }
            }
        }
        .listStyle(.sidebar)
        .navigationSplitViewColumnWidth(min: 220, ideal: 260)
    }
}

struct CatalogDetail: View {
    @Environment(AppModel.self) private var model
    let catalog: CatalogSummary

    var body: some View {
        VStack(spacing: 0) {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    VStack(alignment: .leading, spacing: 6) {
                        Text(catalog.title)
                            .font(.largeTitle.bold())
                        Text(catalog.description)
                            .foregroundStyle(.secondary)
                    }

                    HStack(spacing: 12) {
                        StatCard(label: "Records", value: "\(catalog.count)")
                        StatCard(label: "Complete", value: "\(catalog.completeRecordCount)")
                        StatCard(label: "Partial", value: "\(catalog.partialRecordCount)")
                        StatCard(label: "Images", value: "\(catalog.imageCount)")
                        StatCard(label: "Structures", value: "\(catalog.structureCount)")
                    }

                    if !catalog.measuredProvenance.isEmpty {
                        VStack(alignment: .leading, spacing: 6) {
                            Text("Measured provenance")
                                .font(.headline)
                            ForEach(catalog.measuredProvenance.sorted(by: { $0.key < $1.key }), id: \.key) { key, value in
                                HStack {
                                    Text(key)
                                        .font(.system(.body, design: .monospaced))
                                    Spacer()
                                    Text("\(value)")
                                        .foregroundStyle(.secondary)
                                }
                            }
                        }
                    }

                    VStack(alignment: .leading, spacing: 6) {
                        Text("Files")
                            .font(.headline)
                        LabeledRow(label: "Sources", value: catalog.source)
                        LabeledRow(label: "Catalog page", value: catalog.readme)
                    }
                }
                .padding(24)
            }

            Divider()
            RunConsole()
                .padding(.horizontal, 24)
                .padding(.vertical, 12)
                .frame(height: 220)
        }
    }
}

struct StatCard: View {
    let label: String
    let value: String

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(label)
                .font(.caption)
                .foregroundStyle(.secondary)
            Text(value)
                .font(.title2.bold())
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.quaternary.opacity(0.4), in: RoundedRectangle(cornerRadius: 10))
    }
}

struct LabeledRow: View {
    let label: String
    let value: String

    var body: some View {
        HStack {
            Text(label)
                .foregroundStyle(.secondary)
            Spacer()
            Text(value)
                .font(.system(.caption, design: .monospaced))
                .textSelection(.enabled)
        }
    }
}

struct RunConsole: View {
    @Environment(AppModel.self) private var model
    @State private var commandID = "catalogs"
    @State private var extraFlags = ""

    private let commands = [
        ("catalogs", "catalogs --check", "consistency gate over index and records"),
        ("drift", "drift", "upstream README and URL drift report"),
        ("verify", "verify", "measure stored evidence (dry run)"),
        ("capture-list", "capture --list", "what own-product capture can run here"),
    ]

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Picker("Command", selection: $commandID) {
                    ForEach(commands, id: \.0) { id, label, description in
                        Text(label).tag(id)
                    }
                }
                .frame(width: 260)
                TextField("extra flags", text: $extraFlags)
                    .font(.system(.body, design: .monospaced))
                    .textFieldStyle(.roundedBorder)
                    .frame(maxWidth: 220)
                Button("Run") {
                    var arguments = commands.first { $0.0 == commandID }?.1.split(separator: " ").map(String.init) ?? []
                    let extras = extraFlags.split(separator: " ").map(String.init)
                    arguments += extras
                    Task { await model.run(arguments) }
                }
                .disabled(model.runState.isRunning)
                Spacer()
            }

            switch model.runState {
            case .idle:
                Text("Run a read-only command against the corpus. Nothing here mutates records.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            case .running(let command):
                HStack(spacing: 8) {
                    ProgressView().controlSize(.small)
                    Text("running \(command)…")
                        .font(.system(.caption, design: .monospaced))
                }
            case .finished(let result):
                ScrollView {
                    Text(result.output.isEmpty ? "(no output)" : result.output)
                        .font(.system(.caption, design: .monospaced))
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .textSelection(.enabled)
                }
                .background(.black.opacity(0.85), in: RoundedRectangle(cornerRadius: 8))
                HStack {
                    Image(systemName: result.succeeded ? "checkmark.circle.fill" : "xmark.circle.fill")
                        .foregroundStyle(result.succeeded ? .green : .red)
                    Text("\(result.command) — exit \(result.exitCode)")
                        .font(.system(.caption, design: .monospaced))
                }
            }
        }
    }
}

extension AppModel.RunState {
    var isRunning: Bool {
        if case .running = self { return true }
        return false
    }
}
