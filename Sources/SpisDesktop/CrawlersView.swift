import SwiftUI

struct CrawlersView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        VStack(spacing: 0) {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Image(systemName: "book.circle")
                        .font(.title2)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Crawlers")
                            .font(.headline)
                        Text("Run evidence capture for interface families")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                    Spacer()
                }

                Text("Six families from evidence corpus:")
                    .font(.caption)
                    .foregroundColor(.secondary)

                VStack(alignment: .leading, spacing: 6) {
                    Group {
                        Text("crawl-mobile: iOS and Android apps").font(.caption)
                        Text("crawl-desktop: macOS and cross-platform").font(.caption)
                        Text("crawl-web: 8 families").font(.caption)
                        Text("crawl-tui: Terminal user interfaces").font(.caption)
                        Text("crawl-cli: Command-line tools").font(.caption)
                        Text("crawl-docs: Documentation sites").font(.caption)
                    }
                    .foregroundColor(.secondary)
                }

                HStack(spacing: 12) {
                    Button(action: { model.load() }) {
                        Label("Reload Catalogs", systemImage: "arrow.clockwise")
                    }

                    Spacer()
                }
                .font(.caption)
            }
            .padding(16)
            .background(Color(.controlBackgroundColor))

            Divider()

            if model.catalogs.isEmpty {
                VStack(spacing: 12) {
                    Image(systemName: "hourglass")
                        .font(.title2)
                        .foregroundColor(.secondary)
                    Text("No catalogs available")
                        .font(.headline)
                    Text("Spis not found or data unavailable")
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .lineLimit(2)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(Color(.controlBackgroundColor))
            } else {
                TabView {
                    CrawlerStartView(model: model)
                        .tabItem {
                            Label("Start", systemImage: "play.fill")
                        }

                    if let runId = model.currentRunId {
                        CrawlerStatusView(model: model, runId: runId)
                            .tabItem {
                                Label("Status", systemImage: "info.circle")
                            }

                        if case .completed(let op) = model.crawlState, !op.isTerminal {
                            CrawlerResumeView(model: model, runId: runId)
                                .tabItem {
                                    Label("Resume", systemImage: "arrowtriangle.right.fill")
                                }
                        }

                        if case .completed(let op) = model.crawlState, op.state == "completed" {
                            CrawlerImportView(model: model, runId: runId)
                                .tabItem {
                                    Label("Import", systemImage: "arrow.down.doc")
                                }
                        }
                    }
                }
            }
        }
        .task { model.load() }
    }
}

struct CrawlerStartView: View {
    let model: AppModel

    var families: [String] {
        ["crawl-mobile", "crawl-desktop", "crawl-web", "crawl-tui", "crawl-cli", "crawl-docs"]
    }

    var body: some View {
        Form {
            Section("Configuration") {
                Picker("Family", selection: Binding(
                    get: { model.selectedCrawlerFamily ?? "crawl-mobile" },
                    set: { model.selectedCrawlerFamily = $0 }
                )) {
                    ForEach(families, id: \.self) { family in
                        Text(family).tag(family)
                    }
                }

                TextField("Host", text: Binding(
                    get: { model.crawlHost ?? "" },
                    set: { model.crawlHost = $0.isEmpty ? nil : $0 }
                ))

                TextField("Record (optional)", text: Binding(
                    get: { model.crawlRecord ?? "" },
                    set: { model.crawlRecord = $0.isEmpty ? nil : $0 }
                ))

                TextField("Admission URL (optional)", text: Binding(
                    get: { model.crawlAdmissionUrl ?? "" },
                    set: { model.crawlAdmissionUrl = $0.isEmpty ? nil : $0 }
                ))
            }

            Section {
                Button(action: model.startCrawl) {
                    switch model.crawlState {
                    case .loading:
                        HStack {
                            ProgressView()
                                .scaleEffect(0.8)
                            Text("Starting...")
                        }
                    default:
                        Text("Start Crawl")
                    }
                }
                .disabled(model.selectedCrawlerFamily == nil || model.crawlHost == nil || model.crawlState == .loading)
            }

            if case .completed(let op) = model.crawlState {
                Section("Result") {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Run ID: \(op.run_id ?? "unknown")")
                            .font(.caption)
                            .monospaced()
                        Text("State: \(op.statusDisplay)")
                            .font(.caption)
                        if let updated = op.updated_at {
                            Text("Updated: \(updated)")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                    }
                }
            } else if case .failed(let error) = model.crawlState {
                Section("Error") {
                    Text(error)
                        .font(.caption)
                        .foregroundColor(.red)
                }
            }
        }
    }
}

struct CrawlerStatusView: View {
    let model: AppModel
    let runId: String

    var body: some View {
        Form {
            Section {
                Button(action: model.checkCrawlStatus) {
                    switch model.crawlState {
                    case .loading:
                        HStack {
                            ProgressView()
                                .scaleEffect(0.8)
                            Text("Loading...")
                        }
                    default:
                        Text("Check Status")
                    }
                }
                .disabled(model.crawlState == .loading)
            }

            if case .completed(let op) = model.crawlState {
                Section("Status") {
                    VStack(alignment: .leading, spacing: 6) {
                        HStack {
                            Text("Run ID").fontWeight(.semibold)
                            Spacer()
                            Text(op.run_id ?? "unknown")
                                .font(.caption)
                                .monospaced()
                        }
                        Divider()
                        HStack {
                            Text("State").fontWeight(.semibold)
                            Spacer()
                            Text(op.statusDisplay)
                                .font(.caption)
                        }
                        if let count = op.counts?["catalog_completed"] {
                            Divider()
                            HStack {
                                Text("Catalogs completed").fontWeight(.semibold)
                                Spacer()
                                Text("\(count)")
                                    .font(.caption)
                            }
                        }
                        if op.totalRecords() > 0 {
                            Divider()
                            HStack {
                                Text("Records total").fontWeight(.semibold)
                                Spacer()
                                Text("\(op.totalRecords())")
                                    .font(.caption)
                            }
                        }
                        if let updated = op.updated_at {
                            Divider()
                            HStack {
                                Text("Updated").fontWeight(.semibold)
                                Spacer()
                                Text(updated)
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }
                        }
                    }
                }

                if !op.isTerminal {
                    Section {
                        Text("Crawl operation running. Check status periodically.")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }
            } else if case .failed(let error) = model.crawlState {
                Section("Error") {
                    Text(error)
                        .font(.caption)
                        .foregroundColor(.red)
                }
            }
        }
    }
}

struct CrawlerResumeView: View {
    let model: AppModel
    let runId: String

    var body: some View {
        Form {
            Section("Resume Interrupted Crawl") {
                Text("Resume the last incomplete crawl run from where it paused.")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }

            Section {
                Button(action: model.resumeCrawl) {
                    switch model.crawlState {
                    case .running(let op):
                        HStack {
                            ProgressView()
                                .scaleEffect(0.8)
                            Text("\(op)...")
                        }
                    default:
                        Text("Resume Crawl")
                    }
                }
                .disabled(model.crawlState == .loading || model.crawlState == .running(operation: "Resuming"))
            }

            if case .completed(let op) = model.crawlState {
                Section("Result") {
                    Text("State: \(op.statusDisplay)")
                        .font(.caption)
                }
            } else if case .failed(let error) = model.crawlState {
                Section("Error") {
                    Text(error)
                        .font(.caption)
                        .foregroundColor(.red)
                }
            }
        }
    }
}

struct CrawlerImportView: View {
    let model: AppModel
    let runId: String

    var body: some View {
        Form {
            Section("Import Crawl Records") {
                Text("Import completed crawl results into the corpus index.")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }

            Section {
                Button(action: model.importCrawlResults) {
                    switch model.crawlState {
                    case .running(let op):
                        HStack {
                            ProgressView()
                                .scaleEffect(0.8)
                            Text("\(op)...")
                        }
                    default:
                        Text("Import Results")
                    }
                }
                .disabled(model.crawlState == .loading || model.crawlState == .running(operation: "Importing"))
            }

            if case .completed(let op) = model.crawlState {
                Section("Result") {
                    Text("State: \(op.statusDisplay)")
                        .font(.caption)
                }
            } else if case .failed(let error) = model.crawlState {
                Section("Error") {
                    Text(error)
                        .font(.caption)
                        .foregroundColor(.red)
                }
            }
        }
    }
}

#Preview {
    CrawlersView()
        .environment(AppModel())
}
