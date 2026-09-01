import SwiftUI

struct CrawlersView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        VStack(spacing: 0) {
            if let error = model.loadError {
                VStack(spacing: 12) {
                    Image(systemName: "exclamationmark.circle")
                        .font(.system(size: 32))
                        .foregroundColor(.red)
                    Text("Could not load Spis")
                        .font(.headline)
                    Text(error)
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                .padding()
            } else if model.catalogs.isEmpty {
                VStack(spacing: 12) {
                    Image(systemName: "questionmark.circle")
                        .font(.system(size: 32))
                        .foregroundColor(.orange)
                    Text("No catalogs found")
                        .font(.headline)
                    Text("Spis is installed but has no catalogs configured.")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                .padding()
            } else {
                ScrollView {
                    VStack(alignment: .leading, spacing: 16) {
                        if case .idle = model.crawlState {
                            CrawlerStartView(model: model)
                        } else if case let .completed(op) = model.crawlState {
                            CrawlerStatusView(model: model, operation: op)
                        } else if case let .failed(error) = model.crawlState {
                            CrawlerFailedView(model: model, error: error)
                        } else if case let .running(opName) = model.crawlState {
                            VStack(spacing: 12) {
                                ProgressView()
                                Text("Running: \(opName)")
                                    .font(.caption)
                            }
                            .padding()
                        }
                    }
                    .padding()
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
                .help("Paste a previous run ID to check its status after app restart")
            }

            Section("Start New Crawl") {
                Picker("Catalog", selection: Binding(
                    get: { model.selectedCatalogForCrawl },
                    set: { model.selectedCatalogForCrawl = $0 }
                )) {
                    Text("All 15 catalogs (crawl-mobile, crawl-desktop, crawl-web, etc.)").tag(nil as CatalogSummary?)
                    Divider()
                    ForEach(model.catalogs) { catalog in
                        Text(catalog.title).tag(catalog as CatalogSummary?)
                    }
                }

                TextField("Host (optional)", text: Binding(
                    get: { model.crawlHost ?? "" },
                    set: { model.crawlHost = $0.isEmpty ? nil : $0 }
                ))
                .help("Optional: crawler target override (hostname, IP, or service alias). Left empty uses default Stado routing.")

                TextField("Record (optional)", text: Binding(
                    get: { model.crawlRecord ?? "" },
                    set: { model.crawlRecord = $0.isEmpty ? nil : $0 }
                ))
                .help("Specific record ID, or leave empty to crawl all records in selected catalog")

                TextField("Browser Service (optional)", text: Binding(
                    get: { model.crawlAdmissionUrl ?? "" },
                    set: { model.crawlAdmissionUrl = $0.isEmpty ? nil : $0 }
                ))
                .help("Optional: browser service endpoint URL (e.g., http://localhost:3000 for local dev)")
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
                    model.crawlState == .loading
                )
            }

            if case .completed(let op) = model.crawlState {
                Section("Last Result Summary") {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Run ID: \(op.run_id ?? "unknown")")
                            .font(.caption)
                            .monospaced()
                        Text("State: \(stateLabel(op.statusDisplay))")
                            .font(.caption)
                        if let updated = op.updated_at {
                            Text("Updated: \(updated)")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                    }
                    
                    HStack {
                        Button(action: { model.resetCrawl() }) {
                            HStack {
                                Image(systemName: "arrow.counterclockwise")
                                Text("New Crawl")
                            }
                        }
                        
                        if op.statusDisplay == "completed" || op.statusDisplay == "uploaded" {
                            Button(action: model.importCrawlResults) {
                                HStack {
                                    Image(systemName: "arrow.down.doc")
                                    Text("Import Results")
                                }
                            }
                        }
                        
                        if op.statusDisplay == "failed" || op.statusDisplay == "cancelled" || op.statusDisplay == "partial" {
                            Button(action: model.resumeCrawl) {
                                HStack {
                                    Image(systemName: "play.circle")
                                    Text("Resume")
                                }
                            }
                        }
                    }
                }
            } else if case .failed(let error) = model.crawlState {
                Section("Error") {
                    Text(error)
                        .font(.caption)
                        .foregroundColor(.red)
                    
                    Button(action: { model.resetCrawl() }) {
                        HStack {
                            Image(systemName: "arrow.counterclockwise")
                            Text("New Crawl")
                        }
                    }
                }
            }
        }
    }
    
    private func stateLabel(_ state: String) -> String {
        switch state.lowercased() {
        case "completed": return "✓ Completed"
        case "running": return "⟳ Running"
        case "failed": return "✗ Failed"
        case "partial": return "⊘ Partial"
        case "cancelled": return "■ Cancelled"
        case "uploaded": return "⬆ Uploaded"
        default: return state
        }
    }
}

struct CrawlerStatusView: View {
    let model: AppModel
    let operation: CrawlOperation

    var body: some View {
        Form {
            Section("Crawl Operation") {
                HStack {
                    Text("Run ID")
                    Spacer()
                    Text(operation.run_id ?? "unknown")
                        .font(.caption)
                        .monospaced()
                        .foregroundColor(.secondary)
                }
                HStack {
                    Text("Status")
                    Spacer()
                    Text(statusLabel(operation.statusDisplay))
                        .font(.caption)
                        .fontWeight(.semibold)
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
                        DisclosureGroup {
                            VStack(alignment: .leading, spacing: 8) {
                                HStack {
                                    Text("Status:")
                                        .fontWeight(.semibold)
                                    Spacer()
                                    Text(statusLabel(catalog.state))
                                }
                                
                                if let records = catalog.records {
                                    Text("Records: \(records.count)")
                                        .font(.caption)
                                    
                                    if !records.isEmpty {
                                        DisclosureGroup("Record Details (\(records.count))") {
                                            VStack(alignment: .leading, spacing: 4) {
                                                ForEach(records, id: \.record) { record in
                                                    HStack(alignment: .top, spacing: 8) {
                                                        VStack(alignment: .leading, spacing: 2) {
                                                            Text(record.record)
                                                                .font(.caption)
                                                                .monospaced()
                                                            Text("Status: Crawled")
                                                                .font(.caption2)
                                                                .foregroundColor(.secondary)
                                                        }
                                                        Spacer()
                                                    }
                                                }
                                            }
                                        }
                                    }
                                }
                                
                                if let artifactUri = catalog.artifact_uri {
                                    HStack(alignment: .top, spacing: 8) {
                                        Text("Artifact:")
                                            .fontWeight(.semibold)
                                        VStack(alignment: .leading, spacing: 2) {
                                            Text(artifactUri)
                                                .font(.caption)
                                                .monospaced()
                                                .foregroundColor(.blue)
                                                .lineLimit(2)
                                            Text("(local path - copy as needed)")
                                                .font(.caption2)
                                                .foregroundColor(.secondary)
                                        }
                                    }
                                }
                                
                                if let error = catalog.error {
                                    HStack(alignment: .top, spacing: 8) {
                                        Image(systemName: "exclamationmark.triangle")
                                            .foregroundColor(.orange)
                                        VStack(alignment: .leading, spacing: 2) {
                                            Text("Error")
                                                .fontWeight(.semibold)
                                                .font(.caption)
                                            Text(error)
                                                .font(.caption2)
                                        }
                                    }
                                }
                            }
                            .padding(.vertical, 4)
                        } label: {
                            HStack {
                                Text(catalog.catalog)
                                    .fontWeight(.semibold)
                                Spacer()
                                if let records = catalog.records {
                                    Text("\(records.count) records")
                                        .font(.caption)
                                        .foregroundColor(.secondary)
                                }
                            }
                        }
                    }
                }
            }

            if let counts = operation.counts {
                Section("Record Summary") {
                    VStack(alignment: .leading, spacing: 6) {
                        HStack {
                            Text("✓ Completed:")
                            Spacer()
                            Text("\(counts["record_completed"] ?? 0)")
                                .fontWeight(.semibold)
                        }
                        HStack {
                            Text("⊘ Partial:")
                            Spacer()
                            Text("\(counts["record_partial"] ?? 0)")
                                .fontWeight(.semibold)
                        }
                        HStack {
                            Text("✗ Failed:")
                            Spacer()
                            Text("\(counts["record_failed"] ?? 0)")
                                .fontWeight(.semibold)
                        }
                        HStack {
                            Text("⧖ Skipped:")
                            Spacer()
                            Text("\(counts["record_skipped"] ?? 0)")
                                .fontWeight(.semibold)
                        }
                    }
                }
            }

            Section {
                HStack {
                    Button(action: { model.resetCrawl() }) {
                        HStack {
                            Image(systemName: "arrow.counterclockwise")
                            Text("New Crawl")
                        }
                    }
                    
                    if operation.statusDisplay == "completed" || operation.statusDisplay == "uploaded" {
                        Button(action: model.importCrawlResults) {
                            HStack {
                                Image(systemName: "arrow.down.doc")
                                Text("Import Results")
                            }
                        }
                    }
                    
                    if operation.statusDisplay == "failed" || operation.statusDisplay == "cancelled" || operation.statusDisplay == "partial" {
                        Button(action: model.resumeCrawl) {
                            HStack {
                                Image(systemName: "play.circle")
                                Text("Resume")
                            }
                        }
                    }
                }
            }
        }
    }
    
    private func statusLabel(_ state: String) -> String {
        switch state.lowercased() {
        case "completed": return "✓ Completed"
        case "running": return "⟳ Running"
        case "failed": return "✗ Failed"
        case "partial": return "⊘ Partial"
        case "cancelled": return "■ Cancelled"
        case "uploaded": return "⬆ Uploaded"
        default: return state
        }
    }
}

struct CrawlerFailedView: View {
    let model: AppModel
    let error: String

    var body: some View {
        Form {
            Section("Operation Failed") {
                VStack(alignment: .leading, spacing: 8) {
                    Image(systemName: "exclamationmark.circle")
                        .font(.system(size: 24))
                        .foregroundColor(.red)
                    
                    Text("Crawl operation failed")
                        .font(.headline)
                    
                    Text(error)
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                
                Button(action: { model.resetCrawl() }) {
                    HStack {
                        Image(systemName: "arrow.counterclockwise")
                        Text("New Crawl")
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
