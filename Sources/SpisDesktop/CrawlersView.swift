import SwiftUI

struct CrawlersView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        VStack(spacing: 0) {
            if model.catalogs.isEmpty {
                Text("Loading...")
                    .foregroundColor(.secondary)
            } else {
                switch model.crawlState {
                case .idle:
                    CrawlerStartView(model: model)
                case .loading:
                    VStack(spacing: 12) {
                        ProgressView()
                        Text("Starting new crawl...")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                    .padding()
                case .running(let operation):
                    VStack(spacing: 12) {
                        ProgressView()
                        Text(operation)
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                    .padding()
                case .completed(let op):
                    CrawlerStatusView(model: model, operation: op)
                case .failed(let error):
                    CrawlerFailedView(model: model, error: error)
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
            Section("Start New Crawl") {
                Picker("Product Family", selection: Binding(
                    get: { model.selectedCatalogForCrawl },
                    set: { model.selectedCatalogForCrawl = $0 }
                )) {
                    Text("All 15 product families").tag(nil as CatalogSummary?)
                    Divider()
                    ForEach(model.catalogs) { catalog in
                        Text(catalog.title).tag(catalog as CatalogSummary?)
                    }
                }

                TextField("Record (optional)", text: Binding(
                    get: { model.crawlRecord ?? "" },
                    set: { model.crawlRecord = $0.isEmpty ? nil : $0 }
                ))
                .help("Specific record ID (disabled when 'All 15 product families' selected). Leave empty to crawl all records")
                .disabled(model.selectedCatalogForCrawl == nil)

                TextField("Host (optional)", text: Binding(
                    get: { model.crawlHost ?? "" },
                    set: { model.crawlHost = $0.isEmpty ? nil : $0 }
                ))
                .help("Stado target override")

                TextField("Weles admission URL (optional)", text: Binding(
                    get: { model.crawlAdmissionUrl ?? "" },
                    set: { model.crawlAdmissionUrl = $0.isEmpty ? nil : $0 }
                ))
                .help("Weles credential bridge endpoint; if not specified, defaults from repository are used")
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
                .disabled(model.crawlState == .loading)
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
                        .textSelection(.enabled)
                        .foregroundColor(.secondary)
                }
                
                if let revision = operation.source_revision {
                    HStack(alignment: .top) {
                        Text("Revision")
                        Spacer()
                        VStack(alignment: .trailing, spacing: 2) {
                            Text(revision)
                                .font(.caption)
                                .monospaced()
                                .lineLimit(nil)
                                .textSelection(.enabled)
                                .foregroundColor(.secondary)
                        }
                    }
                }
                
                HStack {
                    Text("Status")
                    Spacer()
                    Text(statusLabel(operation.state ?? "unknown"))
                        .font(.caption)
                        .fontWeight(.semibold)
                        .foregroundColor(stateColor(operation.state ?? "unknown"))
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
                ForEach(catalogs, id: \.catalog) { catalog in
                    Section(catalog.catalog) {
                        VStack(alignment: .leading, spacing: 12) {
                            HStack {
                                Text("Status:")
                                    .fontWeight(.semibold)
                                Spacer()
                                Text(statusLabel(catalog.state))
                                    .foregroundColor(stateColor(catalog.state))
                            }
                            
                            if let preflight = catalog.preflight {
                                DisclosureGroup("Preflight Diagnostics") {
                                    VStack(alignment: .leading, spacing: 8) {
                                        HStack {
                                            Text("Overall Ready:")
                                                .fontWeight(.semibold)
                                            Spacer()
                                            Text(preflight.ready ?? false ? "✓ Yes" : "✗ No")
                                                .foregroundColor(preflight.ready ?? false ? .green : .red)
                                        }
                                        
                                        HStack {
                                            Text("Schema:")
                                            Spacer()
                                            Text(preflight.schema ?? "unknown")
                                                .font(.caption)
                                                .monospaced()
                                        }
                                        
                                        if let cat = preflight.catalog {
                                            HStack {
                                                Text("Catalog:")
                                                Spacer()
                                                Text(cat)
                                                    .font(.caption)
                                                    .monospaced()
                                            }
                                        }
                                        
                                        if let engine = preflight.engine {
                                            HStack {
                                                Text("Engine:")
                                                Spacer()
                                                Text(engine)
                                                    .font(.caption)
                                                    .monospaced()
                                            }
                                        }
                                        
                                        if let host = preflight.host {
                                            HStack {
                                                Text("Host:")
                                                Spacer()
                                                Text(host)
                                                    .font(.caption)
                                                    .monospaced()
                                            }
                                        }
                                        
                                        if let checks = preflight.checks, !checks.isEmpty {
                                            Divider()
                                            Text("Checks").fontWeight(.semibold).font(.caption)
                                            
                                            ForEach(Array(checks.enumerated()), id: \.offset) { idx, check in
                                                VStack(alignment: .leading, spacing: 4) {
                                                    HStack {
                                                        Text("Check \(idx + 1):")
                                                            .fontWeight(.semibold)
                                                            .font(.caption)
                                                        Spacer()
                                                        Text(check.ready ?? false ? "✓ Ready" : "✗ Not Ready")
                                                            .font(.caption)
                                                            .foregroundColor(check.ready ?? false ? .green : .orange)
                                                    }
                                                    
                                                    if let cmd = check.command, !cmd.isEmpty {
                                                        Text("Command: \(cmd.joined(separator: " "))")
                                                            .font(.caption2)
                                                            .monospaced()
                                                            .lineLimit(nil)
                                                            .textSelection(.enabled)
                                                            .foregroundColor(.secondary)
                                                    }
                                                    
                                                    if let stdout = check.stdout {
                                                        Text("stdout: \(stdout)")
                                                            .font(.caption2)
                                                            .monospaced()
                                                            .lineLimit(nil)
                                                            .textSelection(.enabled)
                                                            .foregroundColor(.secondary)
                                                    }
                                                    
                                                    if let stderr = check.stderr {
                                                        Text("stderr: \(stderr)")
                                                            .font(.caption2)
                                                            .monospaced()
                                                            .lineLimit(nil)
                                                            .textSelection(.enabled)
                                                            .foregroundColor(.red)
                                                    }
                                                    
                                                    if let error = check.error {
                                                        Text("error: \(error)")
                                                            .font(.caption2)
                                                            .monospaced()
                                                            .lineLimit(nil)
                                                            .textSelection(.enabled)
                                                            .foregroundColor(.red)
                                                    }
                                                }
                                                .padding(.vertical, 2)
                                            }
                                        }
                                        
                                        if let records = preflight.records, !records.isEmpty {
                                            Divider()
                                            Text("Record Preflight Checks").fontWeight(.semibold).font(.caption)
                                            
                                            ForEach(records, id: \.record) { record in
                                                VStack(alignment: .leading, spacing: 4) {
                                                    HStack {
                                                        VStack(alignment: .leading, spacing: 2) {
                                                            Text(record.record ?? "unknown")
                                                                .font(.caption)
                                                                .monospaced()
                                                                .fontWeight(.semibold)
                                                            if let name = record.name {
                                                                Text(name).font(.caption2).foregroundColor(.secondary)
                                                            }
                                                        }
                                                        Spacer()
                                                        Text(record.ready ?? false ? "✓ Ready" : "✗ Not Ready")
                                                            .font(.caption)
                                                            .foregroundColor(record.ready ?? false ? .green : .orange)
                                                    }
                                                    
                                                    if let binding = record.account_binding {
                                                        Text("Account: \(binding)")
                                                            .font(.caption2)
                                                            .textSelection(.enabled)
                                                            .lineLimit(nil)
                                                            .foregroundColor(.secondary)
                                                    }
                                                    
                                                    if let runtime = record.required_runtime_product {
                                                        Text("Runtime: \(runtime)")
                                                            .font(.caption2)
                                                            .textSelection(.enabled)
                                                            .foregroundColor(.secondary)
                                                    }
                                                    
                                                    if let diagnostic = record.diagnostic {
                                                        Text("Diagnostic: \(diagnostic)")
                                                            .font(.caption2)
                                                            .monospaced()
                                                            .lineLimit(nil)
                                                            .textSelection(.enabled)
                                                            .foregroundColor(.secondary)
                                                    }
                                                    
                                                    if let checks = record.checks, !checks.isEmpty {
                                                        ForEach(Array(checks.enumerated()), id: \.offset) { idx, check in
                                                            VStack(alignment: .leading, spacing: 2) {
                                                                HStack {
                                                                    Text("Check \(idx + 1)").font(.caption2).fontWeight(.semibold)
                                                                    Spacer()
                                                                    Text(check.ready ?? false ? "✓" : "✗")
                                                                        .foregroundColor(check.ready ?? false ? .green : .orange)
                                                                }
                                                                if let cmd = check.command {
                                                                    Text(cmd.joined(separator: " "))
                                                                        .font(.caption2)
                                                                        .monospaced()
                                                                        .lineLimit(nil)
                                                                        .textSelection(.enabled)
                                                                        .foregroundColor(.secondary)
                                                                }
                                                            }
                                                        }
                                                    }
                                                }
                                                .padding(.vertical, 2)
                                            }
                                        }
                                        
                                        if let weles = preflight.weles {
                                            Divider()
                                            Text("Weles Info").fontWeight(.semibold).font(.caption)
                                            
                                            if let url = weles.admission_url {
                                                Text("Admission URL: \(url)")
                                                    .font(.caption2)
                                                    .monospaced()
                                                    .lineLimit(nil)
                                                    .textSelection(.enabled)
                                                    .foregroundColor(.blue)
                                            }
                                            
                                            if let ready = weles.admission_transport_ready {
                                                HStack {
                                                    Text("Transport Ready:")
                                                        .font(.caption2)
                                                    Spacer()
                                                    Text(ready ? "✓ Yes" : "✗ No")
                                                        .font(.caption2)
                                                        .foregroundColor(ready ? .green : .orange)
                                                }
                                            }
                                            
                                            if let binding = weles.account_binding {
                                                Text("Account: \(binding)")
                                                    .font(.caption2)
                                                    .textSelection(.enabled)
                                                    .lineLimit(nil)
                                                    .foregroundColor(.secondary)
                                            }
                                        }
                                    }
                                    .padding(.vertical, 4)
                                }
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
                                                            .foregroundColor(stateColor(record.state))
                                                    }
                                                    
                                                    if let gaps = record.gaps, !gaps.isEmpty {
                                                        HStack(alignment: .top, spacing: 4) {
                                                            Image(systemName: "exclamationmark.circle")
                                                                .font(.caption2)
                                                                .foregroundColor(.orange)
                                                            Text("Gaps: \(gaps.joined(separator: ", "))")
                                                                .font(.caption2)
                                                                .foregroundColor(.orange)
                                                                .lineLimit(nil)
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
                                                                .lineLimit(nil)
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
                                            .textSelection(.enabled)
                                            .foregroundColor(.blue)
                                            .lineLimit(nil)
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
                                            .lineLimit(nil)
                                    }
                                }
                            }
                        }
                    }
                }
            }

            if let counts = operation.counts, !counts.isEmpty {
                let catalogCounts = counts.filter { $0.key.hasPrefix("catalog_") }
                let recordCounts = counts.filter { $0.key.hasPrefix("record_") }
                
                if !catalogCounts.isEmpty || !recordCounts.isEmpty {
                    Section("Summary") {
                        VStack(alignment: .leading, spacing: 8) {
                            if !catalogCounts.isEmpty {
                                Text("Catalogs").fontWeight(.semibold).font(.caption)
                                ForEach(catalogCounts.sorted(by: { $0.key < $1.key }), id: \.key) { key, count in
                                    HStack {
                                        Text(displayLabel(for: key))
                                        Spacer()
                                        Text("\(count)")
                                            .fontWeight(.semibold)
                                    }
                                    .font(.caption)
                                }
                            }
                            
                            if !recordCounts.isEmpty {
                                if !catalogCounts.isEmpty {
                                    Divider()
                                }
                                Text("Records").fontWeight(.semibold).font(.caption)
                                ForEach(recordCounts.sorted(by: { $0.key < $1.key }), id: \.key) { key, count in
                                    HStack {
                                        Text(displayLabel(for: key))
                                        Spacer()
                                        Text("\(count)")
                                            .fontWeight(.semibold)
                                    }
                                    .font(.caption)
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
                    
                    if let state = operation.state {
                        if ["failed", "cancelled", "partial", "preflight_failed", "submission_failed", "lost"].contains(state) {
                            Button(action: model.resumeCrawl) {
                                HStack {
                                    Image(systemName: "play.circle")
                                    Text("Resume")
                                }
                            }
                        }
                        
                        if ["completed", "uploaded"].contains(state) {
                            Button(action: model.importCrawlResults) {
                                HStack {
                                    Image(systemName: "arrow.down.doc")
                                    Text("Import Results")
                                }
                            }
                        }
                    }
                }
            }
        }
    }
    
    private func stateColor(_ state: String) -> Color {
        switch state.lowercased() {
        case "queued", "running":
            return .gray
        case "completed", "imported", "uploaded":
            return .green
        case "failed", "partial", "cancelled", "preflight_failed", "submission_failed", "lost":
            return .red
        default:
            return .gray
        }
    }
    
    private func statusLabel(_ state: String) -> String {
        switch state.lowercased() {
        case "completed": return "✓ Completed"
        case "running": return "⟳ Running"
        case "failed": return "✗ Failed"
        case "partial": return "⊘ Partial"
        case "cancelled": return "■ Cancelled"
        case "preflight_failed": return "✗ Preflight Failed"
        case "submission_failed": return "✗ Submission Failed"
        case "lost": return "⁇ Lost"
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
        let label = key.hasPrefix("record_") ? String(key.dropFirst(7)) : 
                   key.hasPrefix("catalog_") ? String(key.dropFirst(8)) : key
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
        VStack(alignment: .leading, spacing: 16) {
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .font(.title3)
                        .foregroundColor(.red)
                    Text("Crawl Failed")
                        .font(.headline)
                }
                
                Text(error)
                    .font(.caption)
                    .textSelection(.enabled)
                    .foregroundColor(.secondary)
                    .lineLimit(nil)
            }
            .padding()
            .background(Color(.controlBackgroundColor))
            .cornerRadius(8)
            
            HStack {
                Button(action: { model.resetCrawl() }) {
                    HStack {
                        Image(systemName: "arrow.counterclockwise")
                        Text("Try Again")
                    }
                    .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
            }
            .padding()
            
            Spacer()
        }
        .padding()
    }
}

#Preview {
    CrawlersView()
        .environment(AppModel())
}
