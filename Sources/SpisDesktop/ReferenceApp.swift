import AppKit
import SwiftUI
import WisentDesignSystem
import WisentDesktopUpdate

@main
struct ReferenceApp: App {
    @NSApplicationDelegateAdaptor(SpisAppDelegate.self) private var delegate

    /// The app's one updater: it drives the scheduled feed checks and backs the
    /// three items `WisentCheckForUpdatesCommand` puts under the app menu. A
    /// second instance would give the menu its own `SPUUpdater`, so the toggles
    /// would report and change settings that the checking updater never reads.
    @StateObject private var updater = WisentUpdater()

    var body: some Scene {
        WindowGroup("Spis") {
            SpisRootContent(model: delegate.model, manageModel: delegate.manageModel)
        }
        .windowToolbarStyle(.unified)
        .commands {
            CommandGroup(after: .appInfo) {
                WisentCheckForUpdatesCommand(updater: updater)
            }
        }
    }
}

/// Guarantees that Spis owns a window at launch. SwiftUI declines to open a
/// fresh window when it has persistent state to restore but the saved view tree
/// no longer exists, and every change to the window's root view invalidates that
/// tree — the `.textSelection` rule below is one such change. The app then comes
/// up alive with `window=0x0` and nothing on screen, which from the outside is
/// indistinguishable from a crash on launch. `wisentEnsureWindow` opens the same
/// content in a plain window whenever the scene has produced none, and answers
/// `nil` on a normal launch; the result is retained because releasing it would
/// close the only window the operator has.
///
/// Both models live here rather than in the `App` struct so the scene and the
/// fallback window read one instance each: a second `AppModel` would give the
/// fallback window its own catalogs, corpus root and run log.
@MainActor
final class SpisAppDelegate: NSObject, NSApplicationDelegate {
    let model = AppModel()
    let manageModel = ManageModel()
    private var fallbackWindow: NSWindow?

    func applicationDidFinishLaunching(_ notification: Notification) {
        DispatchQueue.main.async { [self] in
            fallbackWindow = wisentEnsureWindow(
                title: "Spis",
                size: CGSize(width: 1080, height: 680)
            ) {
                SpisRootContent(model: model, manageModel: manageModel)
            }
        }
    }
}

/// The one description of Spis's window contents, rendered by both the
/// `WindowGroup` scene and the delegate's fallback window so the two can never
/// disagree about what the window holds or which surface is on screen.
private struct SpisRootContent: View {
    let model: AppModel
    let manageModel: ManageModel

    var body: some View {
        AppRootView()
            .environment(model)
            .environment(manageModel)
            .frame(minWidth: 1080, minHeight: 680)
            // Every fact Spis reports is selectable, and therefore
            // copyable. This app exists to state things a person then
            // quotes somewhere else — a corpus path, a page URL, the
            // stdout of a check, a refusal sentence — and SwiftUI's
            // `Text` refuses selection on macOS unless a view asks, which
            // left 46 of 51 text sites in this window dead to Cmd-C while
            // five had been fixed one at a time.
            //
            // `.textSelection` travels through the environment, so one
            // call at the root of the window's content covers all three
            // surfaces the picker switches between — Browse, Docs, Manage —
            // and every screen added after this one. It sits here rather
            // than inside `AppRootView` or on a `NavigationSplitView` column
            // because those are branches: each would answer the question
            // for itself and leave its siblings unselectable. And because
            // this description is what both the scene and the fallback
            // window render, the rule holds in whichever window the operator
            // ends up with, from a single call site.
            .textSelection(.enabled)
            .task { model.load(); manageModel.reloadTypes() }
    }
}

struct AppRootView: View {
    @State private var surface = "browse"

    var body: some View {
        VStack(spacing: 0) {
            Picker("Surface", selection: $surface) {
                Text("Browse").tag("browse")
                Text("Docs").tag("docs")
                Text("Manage").tag("manage")
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .padding(8)

            switch surface {
            case "browse": ContentView()
            case "docs": DocsCorpusView()
            default: ManageView()
            }
        }
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
                Text("Read-only checks against the corpus. Nothing here changes records.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            case .running(let name):
                Text("\(name)…")
                    .font(.caption)
                // The same scrolling box the output lands in, so the console
                // keeps its shape and the bars measure it rather than the
                // window.
                ScrollView {
                    WisentSkeletonText(lines: 4, label: "Running \(name)")
                        .padding(8)
                }
                .background(.black.opacity(0.85), in: RoundedRectangle(cornerRadius: 8))
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
