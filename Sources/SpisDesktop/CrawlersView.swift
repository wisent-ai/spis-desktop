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
                    CrawlerStatusView(model: model, operation: op)
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

    var body: some View {
        Form {
            Section("Load Existing Run (After Restart)") {
                HStack {
                    TextField("Run ID", text: Binding(
                        get: { model.currentRunId ?? "" },
                        set: { newValue in
                            let trimmed = newValue.trimmingCharacters(in: .whitespaces)
                            model.currentRunId = trimmed.isEmpty ? nil : trimmed
                        }
                    ))
                    Button(action: model.checkCrawlStatus) {
                        Image(systemName: "arrow.forward.circle")
                    }
                    .disabled(model.currentRunId == nil || model.currentRunId?.isEmpty == true)
                }
                .help("Paste a previous run ID to check its status")
            }

            Section("Start New Crawl") {
                Picker("Catalog", selection: Binding(
                    get: { model.selectedCatalogForCrawl ?? model.catalogs.first },
                    set: { model.selectedCatalogForCrawl = $0 }
                )) {
                    ForEach(model.catalogs) { catalog in
                        Text(catalog.slug).tag(catalog as CatalogSummary?)
                    }
                }

                TextField("Host", text: Binding(
                    get: { model.crawlHost ?? "" },
                    set: { model.crawlHost = $0.isEmpty ? nil : $0 }
                ))
                .help("Required: crawler target host or IP")

                TextField("Record (optional)", text: Binding(
                    get: { model.crawlRecord ?? "" },
                    set: { model.crawlRecord = $0.isEmpty ? nil : $0 }
                ))
                .help("Specific record ID, or leave empty for all records")

                TextField("Admission URL (optional)", text: Binding(
                    get: { model.crawlAdmissionUrl ?? "" },
                    set: { model.crawlAdmissionUrl = $0.isEmpty ? nil : $0 }
                ))
                .help("Override: credential endpoint or auth token URL")
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
                    model.selectedCatalogForCrawl == nil ||
                    model.crawlHost == nil ||
                    model.crawlState == .loading
                )
            }

            if case .completed(let op) = model.crawlState {
                Section("Last Result") {
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
    let operation: CrawlOperation

    var body: some View {
        Form {
            Section("Crawl Operation Status") {
                HStack {
                    Text("Run ID")
                    Spacer()
                    Text(operation.run_id ?? "unknown")
                        .font(.caption)
                        .monospaced()
                        .foregroundColor(.secondary)
                }
                HStack {
                    Text("State")
                    Spacer()
                    Text(operation.statusDisplay)
                        .font(.caption)
                        .foregroundColor(operation.isError ? .red : .green)
                }
                if let updated = operation.updated_at {
                    HStack {
                        Text("Updated")
                        Spacer()
                        Text(updated)
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }
            }

            if let catalogs = operation.catalogs, !catalogs.isEmpty {
                Section("Catalogs") {
                    ForEach(catalogs, id: \.catalog) { catalog in
                        VStack(alignment: .leading, spacing: 4) {
                            HStack {
                                Text(catalog.catalog)
                                    .font(.caption)
                                    .fontWeight(.semibold)
                                Spacer()
                                Text(catalog.state)
                                    .font(.caption2)
                                    .foregroundColor(.secondary)
                            }
                            if let records = catalog.records {
                                Text("Records: \(records.count)")
                                    .font(.caption2)
                                    .foregroundColor(.secondary)
                            }
                            if let uri = catalog.artifact_uri {
                                Text("Artifacts: \(uri)")
                                    .font(.caption2)
                                    .monospaced()
                                    .foregroundColor(.blue)
                            }
                            if let err = catalog.error {
                                Text("Error: \(err)")
                                    .font(.caption2)
                                    .foregroundColor(.red)
                            }
                        }
                    }
                }
            }

            if let counts = operation.counts, !counts.isEmpty {
                Section("Counts") {
                    ForEach(counts.sorted(by: { $0.key < $1.key }), id: \.key) { key, value in
                        HStack {
                            Text(key.replacingOccurrences(of: "_", with: " ").capitalized)
                            Spacer()
                            Text("\(value)")
                                .font(.caption)
                                .fontWeight(.semibold)
                        }
                    }
                }
            }

            Section {
                Button(action: model.checkCrawlStatus) {
                    Text("Check Status")
                }
                Button(action: model.resumeCrawl) {
                    if case .running = model.crawlState {
                        HStack {
                            ProgressView()
                                .scaleEffect(0.8)
                            Text("Resuming...")
                        }
                    } else {
                        Text("Resume")
                    }
                }
                Button(action: model.importCrawlResults) {
                    if case .running = model.crawlState {
                        HStack {
                            ProgressView()
                                .scaleEffect(0.8)
                            Text("Importing...")
                        }
                    } else {
                        Text("Import Results")
                    }
                }
            }
        }
    }
}

#Preview {
    CrawlersView()
        .environment(AppModel())
}
