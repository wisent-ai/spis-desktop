import SwiftUI

struct CrawlersView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        VStack(spacing: 0) {
            if let error = model.loadError {
                VStack(spacing: 12) {
                    Image(systemName: "exclamationmark.circle")
                        .font(.system(size: 28))
                        .foregroundColor(.orange)
                    Text(error)
                        .font(.caption)
                        .multilineTextAlignment(.center)
                }
                .padding()
                .frame(maxWidth: .infinity)
                Spacer()
            } else if model.catalogs.isEmpty {
                VStack(spacing: 12) {
                    ProgressView()
                    Text("Loading Spis...")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                .padding()
                .frame(maxWidth: .infinity)
                Spacer()
            } else {
                if case .idle = model.crawlState {
                    CrawlerStartView(model: model)
                } else if case let .completed(op) = model.crawlState {
                    CrawlerStatusView(model: model, runId: op.run_id ?? "unknown")
                } else if case let .failed(error) = model.crawlState {
                    VStack(spacing: 12) {
                        Image(systemName: "xmark.circle")
                            .font(.system(size: 28))
                            .foregroundColor(.red)
                        Text("Failed: \(error)")
                            .font(.caption)
                            .multilineTextAlignment(.center)
                    }
                    .padding()
                    .frame(maxWidth: .infinity)
                    Spacer()
                } else {
                    VStack(spacing: 12) {
                        ProgressView()
                        if case let .running(op) = model.crawlState {
                            Text(op)
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                    }
                    .padding()
                    .frame(maxWidth: .infinity)
                    Spacer()
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

    var needsAdmissionUrl: Bool {
        guard let family = model.selectedCrawlerFamily else { return false }
        return family == "crawl-web"
    }

    var needsCatalog: Bool {
        guard let family = model.selectedCrawlerFamily else { return false }
        return family != "crawl-tui" && family != "crawl-cli"
    }

    var body: some View {
        Form {
            Section("Configuration") {
                Picker("Crawler Family", selection: Binding(
                    get: { model.selectedCrawlerFamily ?? "crawl-mobile" },
                    set: { model.selectedCrawlerFamily = $0 }
                )) {
                    ForEach(families, id: \.self) { family in
                        Text(family).tag(family)
                    }
                }

                if needsCatalog {
                    Picker("Catalog", selection: Binding(
                        get: { model.selectedCatalogForCrawl ?? model.catalogs.first },
                        set: { model.selectedCatalogForCrawl = $0 }
                    )) {
                        ForEach(model.catalogs) { catalog in
                            Text(catalog.slug).tag(catalog as CatalogSummary?)
                        }
                    }
                }

                TextField("Host", text: Binding(
                    get: { model.crawlHost ?? "" },
                    set: { model.crawlHost = $0.isEmpty ? nil : $0 }
                ))

                if needsCatalog {
                    TextField("Record (optional)", text: Binding(
                        get: { model.crawlRecord ?? "" },
                        set: { model.crawlRecord = $0.isEmpty ? nil : $0 }
                    ))
                }

                if needsAdmissionUrl {
                    TextField("Admission URL", text: Binding(
                        get: { model.crawlAdmissionUrl ?? "" },
                        set: { model.crawlAdmissionUrl = $0.isEmpty ? nil : $0 }
                    ))
                }
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
                .disabled(
                    model.selectedCrawlerFamily == nil ||
                    model.crawlHost == nil ||
                    (needsCatalog && model.selectedCatalogForCrawl == nil) ||
                    (needsAdmissionUrl && model.crawlAdmissionUrl == nil) ||
                    model.crawlState == .loading
                )
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
            Section("Run Status") {
                HStack {
                    Text("Run ID")
                    Spacer()
                    Text(runId)
                        .font(.caption)
                        .monospaced()
                        .foregroundColor(.secondary)
                }
            }

            Section {
                Button(action: model.checkCrawlStatus) {
                    Text("Check Status")
                }
                Button(action: model.resumeCrawl) {
                    Text("Resume")
                }
                Button(action: model.importCrawlResults) {
                    Text("Import Results")
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
            Section("Resume Crawl") {
                HStack {
                    Text("Run ID")
                    Spacer()
                    Text(runId)
                        .font(.caption)
                        .monospaced()
                        .foregroundColor(.secondary)
                }
            }

            Section {
                Button(action: model.resumeCrawl) {
                    switch model.crawlState {
                    case .running(let op):
                        HStack {
                            ProgressView()
                                .scaleEffect(0.8)
                            Text(op)
                        }
                    default:
                        Text("Resume Crawl")
                    }
                }
                .disabled(model.crawlState == .loading || (model.crawlState != .idle && model.crawlState != .running(operation: "Resuming")))
            }
        }
    }
}

struct CrawlerImportView: View {
    let model: AppModel
    let runId: String

    var body: some View {
        Form {
            Section("Import Results") {
                HStack {
                    Text("Run ID")
                    Spacer()
                    Text(runId)
                        .font(.caption)
                        .monospaced()
                        .foregroundColor(.secondary)
                }
            }

            Section {
                Button(action: model.importCrawlResults) {
                    switch model.crawlState {
                    case .running(let op):
                        HStack {
                            ProgressView()
                                .scaleEffect(0.8)
                            Text(op)
                        }
                    default:
                        Text("Import Results")
                    }
                }
                .disabled(model.crawlState == .loading || (model.crawlState != .idle && model.crawlState != .running(operation: "Importing")))
            }
        }
    }
}

#Preview {
    CrawlersView()
        .environment(AppModel())
}
