import SwiftUI
import WisentDesignSystem

// Browsing a catalogue: the content pane, the sidebar, one catalogue's
// detail, the small cards it is built from, and the run console below it.
//
// Split out of `ReferenceApp.swift`, which had grown past the
// three-hundred-line limit; the app, its delegate and the window's root
// stay there.


struct ContentView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        NavigationSplitView {
            CatalogSidebar()
        } detail: {
            if let error = model.loadError {
                ContentUnavailableView(
                    "Spis unavailable",
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
        }
    }
}

struct RunConsole: View {
    @Environment(AppModel.self) private var model
    @State private var operation: SpisOperation = .catalogsCheck

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Picker("Operation", selection: $operation) {
                    ForEach(SpisOperation.allCases) { operation in
                        Text(operation.displayName).tag(operation)
                    }
                }
                .labelsHidden()
                .frame(width: 240)
                Text(operation.summary)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                Button("Run") {
                    Task { await model.run(operation) }
                }
                .disabled(model.runState.isRunning)
                Spacer()
            }

            switch model.runState {
            case .idle:
                EmptyView()
            case .running(let name):
                // An operation already in flight, not content being read: the
                // console has no output yet to stand in for, so it reports the
                // operation's real status until the output lands.
                WisentProgressPanel(
                    title: name,
                    detail: "Spis is running this operation. Its output appears here when it finishes."
                )
            case .finished(let outcome):
                ScrollView {
                    Text(outcome.output.isEmpty ? "(no output)" : outcome.output)
                        .font(.system(.caption, design: .monospaced))
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .background(.black.opacity(0.85), in: RoundedRectangle(cornerRadius: 8))
                HStack {
                    Image(systemName: outcome.succeeded ? "checkmark.circle.fill" : "xmark.circle.fill")
                        .foregroundStyle(outcome.succeeded ? .green : .red)
                    Text(outcome.refusal ?? "\(outcome.operation) finished")
                        .font(.caption)
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
