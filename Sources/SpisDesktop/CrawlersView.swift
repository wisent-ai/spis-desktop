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
                        } else if case .loading = model.crawlState {
                            VStack(spacing: 12) {
                                ProgressView()
                                Text("Starting crawl...")
                                    .font(.caption)
                            }
                            .padding()
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
                    Text("All 15 catalogs").tag(nil as CatalogSummary?)
                    Divider()
                    ForEach(model.catalogs) { catalog in
                        Text(catalog.title).tag(catalog as CatalogSummary?)
                    }
                }

                TextField("Host (optional)", text: Binding(
                    get: { model.crawlHost ?? "" },
                    set: { model.crawlHost = $0.isEmpty ? nil : $0 }
                ))
                .help("Stado target override")

                TextField("Record (optional)", text: Binding(
                    get: { model.crawlRecord ?? "" },
                    set: { model.crawlRecord = $0.isEmpty ? nil : $0 }
                ))
                .help("Specific record ID (disabled when 'All catalogs' selected). Leave empty to crawl all records in selected catalog")
                .disabled(model.selectedCatalogForCrawl == nil)

                TextField("Browser Service (optional)", text: Binding(
                    get: { model.crawlAdmissionUrl ?? "" },
                    set: { model.crawlAdmissionUrl = $0.isEmpty ? nil : $0 }
                ))
                .help("Optional: browser service endpoint URL")
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
                    model.crawlState == .loading
                )
            }

            if case .completed(let op) = model.crawlState {
                Section("Last Result Summary") {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Run ID: \(op.run_id ?? "unknown")")
                            .font(.caption)
                            .monospaced()
                        Text("State: \(stateLabel(op.state ?? "unknown"))")
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
                        
                        if let state = op.state, ["completed", "uploaded"].contains(state) {
                            Button(action: model.importCrawlResults) {
                                HStack {
                                    Image(systemName: "arrow.down.doc")
                                    Text("Import Results")
                                }
                            }
                        }
                        
                        if let state = op.state, ["failed", "cancelled", "partial"].contains(state) {
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
        case "queued": return "⧖ Queued"
        case "pending_review": return "⋯ Pending Review"
        case "imported": return "✔ Imported"
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
                    Text(statusLabel(operation.state ?? "unknown"))
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
                                            VStack(alignment: .leading, spacing: 6) {
                                                ForEach(records, id: \.record) { record in
                                                    VStack(alignment: .leading, spacing: 2) {
                                                        HStack {
                                                            Text(record.record)
                                                                .font(.caption)
                                                                .monospaced()
                                                            Spacer()
                                                            Text(statusLabel(record.state))
                                                                .font(.caption2)
                                                                .fontWeight(.semibold)
                                                        }
                                                        
                                                        if let gaps = record.gaps, !gaps.isEmpty {
                                                            HStack(alignment: .top, spacing: 4) {
                                                                Image(systemName: "exclamationmark.circle")
                                                                    .font(.caption2)
                                                                    .foregroundColor(.orange)
                                                                Text("Gaps: \(gaps.joined(separator: ", "))")
                                                                    .font(.caption2)
                                                                    .foregroundColor(.orange)
                                                            }
                                                        }
                                                        
                                                        if let error = record.error {
                                                            HStack(alignment: .top, spacing: 4) {
                                                                Image(systemName: "xmark.circle")
                                                                    .font(.caption2)
                                                                    .foregroundColor(.red)
                                                                Text(error)
                                                                    .font(.caption2)
                                                                    .foregroundColor(.red)
                                                            }
                                                        }
                                                    }
                                                    .padding(.vertical, 2)
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
                                            if artifactUri.hasPrefix("stado://") {
                                                Text("(Stado service reference - internal crawl artifact storage)")
                                                    .font(.caption2)
                                                    .foregroundColor(.secondary)
                                            } else {
                                                Text("(Local or external artifact location)")
                                                    .font(.caption2)
                                                    .foregroundColor(.secondary)
                                            }
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
                                Text(catalogTitle(slug: catalog.catalog))
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

            if let counts = operation.counts, !counts.isEmpty {
                let sortedCounts = counts
                    .filter { $0.value > 0 }
                    .sorted { $0.key < $1.key }
                
                if !sortedCounts.isEmpty {
                    Section("Record Summary") {
                        VStack(alignment: .leading, spacing: 6) {
                            ForEach(sortedCounts, id: \.key) { key, count in
                                HStack {
                                    Text(displayLabel(for: key))
                                    Spacer()
                                    Text("\(count)")
                                        .fontWeight(.semibold)
                                }
                            }
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
                    
                    if let state = operation.state, ["completed", "uploaded"].contains(state) {
                        Button(action: model.importCrawlResults) {
                            HStack {
                                Image(systemName: "arrow.down.doc")
                                Text("Import Results")
                            }
                        }
                    }
                    
                    if let state = operation.state, ["queued", "running"].contains(state) {
                        Button(action: model.checkCrawlStatus) {
                            HStack {
                                Image(systemName: "arrow.clockwise")
                                Text("Refresh")
                            }
                        }
                    }
                    
                    if let state = operation.state, ["failed", "cancelled", "partial"].contains(state) {
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
        case "queued": return "⧖ Queued"
        case "pending_review": return "⋯ Pending Review"
        case "imported": return "✔ Imported"
        default: return state
        }
    }
    
    private func catalogTitle(slug: String) -> String {
        model.catalogs.first(where: { $0.slug == slug })?.title ?? slug
    }
    
    private func displayLabel(for key: String) -> String {
        let label = key.hasPrefix("record_") ? String(key.dropFirst(7)) : key
        let emoji: [String: String] = [
            "completed": "✓",
            "partial": "⊘",
            "failed": "✗",
            "skipped": "⊘",
            "imported": "✔",
            "queued": "⧖",
            "running": "⟳"
        ]
        let prefix = emoji[label] ?? "•"
        return "\(prefix) \(label.capitalized)"
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
