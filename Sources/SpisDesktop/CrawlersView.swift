import SwiftUI
import WisentDesignSystem

struct CrawlersView: View {
    @Environment(AppModel.self) private var model
    @State private var refreshTimer: Timer?
    @State private var existingRunId = ""

    var body: some View {
        if let error = model.loadError {
            errorStateView(error)
        } else if model.catalogs.isEmpty {
            emptyStateView()
        } else {
            mainStateView()
        }
    }
    
    @ViewBuilder
    private func errorStateView(_ error: String) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Image(systemName: "exclamationmark.circle.fill")
                    .font(.title2)
                    .foregroundColor(.orange)
                Text("Failed to load catalogs")
                    .font(.headline)
            }
            Text(error)
                .font(.caption)
                .textSelection(.enabled)
                .foregroundColor(.secondary)
                .lineLimit(nil)
            HStack {
                Button(action: model.load) {
                    HStack {
                        Image(systemName: "arrow.clockwise")
                        Text("Retry")
                    }
                    .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
                Spacer()
            }
        }
        .padding()
    }
    
    @ViewBuilder
    private func emptyStateView() -> some View {
        VStack(spacing: 12) {
            Text("No catalogs found")
                .font(.headline)
            Text("Install a Spis reference corpus and ensure the path is correct.")
                .font(.caption)
                .foregroundColor(.secondary)
        }
        .padding()
    }
    
    @ViewBuilder
    private func mainStateView() -> some View {
        VStack(spacing: 0) {
            switch model.crawlState {
            case .idle:
                idleFormView()
            case .loading:
                loadingView("Starting new crawl", "Registering the run with Spis and waiting for its run ID.")
            case .running(let msg):
                loadingView("Crawl running", msg)
            case .completed(let op):
                completedFormView(op)
            case .failed(let err):
                failedFormView(err)
            }
        }
        .task { model.load() }
    }
    
    /// An operation already in flight, not content being read: a crawl has no
    /// unloaded shape to stand in for, so it reports its real status instead.
    @ViewBuilder
    private func loadingView(_ title: String, _ detail: String) -> some View {
        WisentProgressPanel(title: title, detail: detail)
            .padding()
    }
    
    @ViewBuilder
    private func idleFormView() -> some View {
        Form {
            Section("Load Existing Run") {
                loadExistingSection()
            }
            
            Section("Start New Crawl") {
                newCrawlSection()
            }
            
            Section {
                // The control's own action is in flight. This is what
                // `WisentAction(isBusy:)` does in the shell's action bar, and
                // Spis's crawl form is native `Form` chrome rather than a
                // `WisentActionButton`, so it does the same thing by hand: the
                // box, the verb and the resting accessible name all stay, the
                // word underneath keeps sizing the button so it cannot reflow,
                // and a bar shimmers over it. A running crawl also refuses a
                // second press, which is what `disableStart` already reports.
                let isStarting = model.crawlState == .loading
                Button(action: model.startCrawl) {
                    Text("Start Crawl")
                        .opacity(isStarting ? 0 : 1)
                        .overlay {
                            if isStarting {
                                WisentSkeleton(.line, height: 10)
                            }
                        }
                }
                .accessibilityLabel("Start Crawl")
                .disabled(disableStart())
            }
        }
    }
    
    @ViewBuilder
    private func loadExistingSection() -> some View {
        TextField("Run ID (optional)", text: $existingRunId)
            .help("Paste a run ID to manually reattach to a crawl session and check its status. Persisted runs are identified by Spis core.")
        
        HStack {
            Button(action: {
                let trimmed = existingRunId.trimmingCharacters(in: .whitespaces)
                if !trimmed.isEmpty {
                    model.currentRunId = trimmed
                    model.checkCrawlStatus()
                }
            }) {
                HStack {
                    Image(systemName: "magnifyingglass")
                    Text("Check Status")
                }
                .frame(maxWidth: .infinity)
            }
            .buttonStyle(.bordered)
            .disabled(existingRunId.trimmingCharacters(in: .whitespaces).isEmpty)
            
            if !existingRunId.isEmpty {
                Button(action: { existingRunId = "" }) {
                    Image(systemName: "xmark.circle.fill")
                }
                .buttonStyle(.plain)
                .foregroundColor(.secondary)
            }
        }
    }
    
    @ViewBuilder
    private func newCrawlSection() -> some View {
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
        
        let allSelected = model.selectedCatalogForCrawl == nil
        TextField("Record (optional)", text: Binding(
            get: { model.crawlRecord ?? "" },
            set: { model.crawlRecord = $0.isEmpty ? nil : $0 }
        ))
        .disabled(allSelected)
        .help("Specific record ID. Leave empty to crawl all records in the selected family.")
        
        TextField("Host (optional)", text: Binding(
            get: { model.crawlHost ?? "" },
            set: { model.crawlHost = $0.isEmpty ? nil : $0 }
        ))
        .help("Stado target override. If not specified, Stado-selected host is used.")
        
        TextField("Weles admission URL (optional)", text: Binding(
            get: { model.crawlAdmissionUrl ?? "" },
            set: { model.crawlAdmissionUrl = $0.isEmpty ? nil : $0 }
        ))
        .help("Stado-resolved Weles admission endpoint. If not specified, defaults are used.")
    }
    
    private func disableStart() -> Bool {
        if case .loading = model.crawlState { return true }
        return false
    }
    
    @ViewBuilder
    private func completedFormView(_ op: CrawlOperation) -> some View {
        Form {
            Section("Crawl Operation") {
                operationStatusView(op)
            }
            
            if let catalogs = op.catalogs, !catalogs.isEmpty {
                ForEach(catalogs, id: \.catalog) { cat in
                    catalogDetailView(cat)
                }
            }
            
            if let counts = op.counts, !counts.isEmpty {
                Section("Summary") {
                    summaryView(counts)
                }
            }
            
            Section {
                actionButtonsView(op)
            }
        }
        .onChange(of: op.state) { oldState, newState in
            refreshTimer?.invalidate()
            refreshTimer = nil
            if isRunning(op) {
                refreshTimer = Timer.scheduledTimer(withTimeInterval: 3.0, repeats: true) { _ in
                    Task { @MainActor in model.checkCrawlStatus() }
                }
            }
        }
        .onAppear {
            refreshTimer?.invalidate()
            refreshTimer = nil
            if isRunning(op) {
                refreshTimer = Timer.scheduledTimer(withTimeInterval: 3.0, repeats: true) { _ in
                    Task { @MainActor in model.checkCrawlStatus() }
                }
            }
        }
        .onDisappear {
            refreshTimer?.invalidate()
            refreshTimer = nil
        }
    }
    
    @ViewBuilder
    private func operationStatusView(_ op: CrawlOperation) -> some View {
        HStack {
            Text("Run ID")
            Spacer()
            Text(op.run_id ?? "unknown")
                .font(.caption)
                .monospaced()
                .textSelection(.enabled)
                .foregroundColor(.secondary)
        }
        
        if let rev = op.source_revision {
            HStack(alignment: .top) {
                Text("Revision")
                Spacer()
                Text(rev)
                    .font(.caption)
                    .monospaced()
                    .lineLimit(nil)
                    .textSelection(.enabled)
                    .foregroundColor(.secondary)
            }
        }
        
        HStack {
            Text("Status")
            Spacer()
            Text(statusLabel(op.state ?? "unknown"))
                .font(.caption)
                .fontWeight(.semibold)
                .foregroundColor(stateColor(op.state ?? "unknown"))
        }
        
        if let updated = op.updated_at {
            HStack {
                Text("Updated")
                Spacer()
                Text(updated)
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
        }
    }
    
    @ViewBuilder
    private func catalogDetailView(_ cat: CrawlOperation.CrawlCatalog) -> some View {
        Section(cat.catalog) {
            HStack {
                Text("Status:")
                Spacer()
                Text(statusLabel(cat.state))
                    .foregroundColor(stateColor(cat.state))
            }
            
            if let pf = cat.preflight {
                preflightDisclosureView(pf)
            }
            
            if let records = cat.records, !records.isEmpty {
                recordsDisclosureView(records)
            }
            
            if let uri = cat.artifact_uri {
                HStack(alignment: .top, spacing: 8) {
                    Text("Artifact:").fontWeight(.semibold)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(uri)
                            .font(.caption2)
                            .monospaced()
                            .lineLimit(nil)
                            .textSelection(.enabled)
                            .foregroundColor(.blue)
                        Text("(service artifact reference)")
                            .font(.caption2)
                            .foregroundColor(.secondary)
                    }
                }
            }
            
            if let outputUri = cat.output_uri {
                HStack(alignment: .top, spacing: 8) {
                    Text("Output:").fontWeight(.semibold)
                    Text(outputUri)
                        .font(.caption2)
                        .monospaced()
                        .lineLimit(nil)
                        .textSelection(.enabled)
                        .foregroundColor(.blue)
                }
            }
            
            if let err = cat.error {
                HStack(alignment: .top, spacing: 8) {
                    Image(systemName: "exclamationmark.triangle")
                        .foregroundColor(.orange)
                    Text(err)
                        .font(.caption2)
                        .lineLimit(nil)
                        .textSelection(.enabled)
                }
            }
        }
    }
    
    @ViewBuilder
    private func preflightDisclosureView(_ pf: CrawlOperation.CrawlCatalog.PreflightDiagnostic) -> some View {
        DisclosureGroup("Preflight Diagnostics") {
            preflightDetailsView(pf)
        }
    }
    
    @ViewBuilder
    private func preflightDetailsView(_ pf: CrawlOperation.CrawlCatalog.PreflightDiagnostic) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Overall Ready:").fontWeight(.semibold)
                Spacer()
                Text(pf.ready ?? false ? "✓ Yes" : "✗ No")
                    .foregroundColor(pf.ready ?? false ? .green : .red)
            }
            .font(.caption)
            
            if let schema = pf.schema {
                HStack {
                    Text("Schema:").font(.caption)
                    Spacer()
                    Text(schema).font(.caption2).monospaced().textSelection(.enabled)
                }
            }
            
            if let cat = pf.catalog {
                HStack {
                    Text("Catalog:").font(.caption)
                    Spacer()
                    Text(cat).font(.caption2).monospaced().textSelection(.enabled)
                }
            }
            
            if let eng = pf.engine {
                HStack {
                    Text("Engine:").font(.caption)
                    Spacer()
                    Text(eng).font(.caption2).monospaced().textSelection(.enabled)
                }
            }
            
            if let host = pf.host {
                HStack {
                    Text("Host:").font(.caption)
                    Spacer()
                    Text(host).font(.caption2).monospaced().textSelection(.enabled)
                }
            }
            
            if let noPrompts = pf.no_permission_prompts_requested {
                HStack {
                    Text("No Permission Prompts:").font(.caption)
                    Spacer()
                    Text(noPrompts ? "✓ Yes" : "✗ No").font(.caption).foregroundColor(noPrompts ? .green : .orange)
                }
            }
            
            if let checks = pf.checks, !checks.isEmpty {
                Divider()
                Text("Checks").fontWeight(.semibold).font(.caption)
                ForEach(Array(checks.enumerated()), id: \.offset) { idx, check in
                    checkDetailsView(idx, check)
                }
            }
            
            if let records = pf.records, !records.isEmpty {
                Divider()
                Text("Record Preflight Checks").fontWeight(.semibold).font(.caption)
                ForEach(records, id: \.record) { record in
                    recordPreflightDetailsView(record)
                }
            }
            
            if let weles = pf.weles {
                Divider()
                Text("Weles Info").fontWeight(.semibold).font(.caption)
                if let url = weles.admission_url {
                    Text("Admission: \(url)")
                        .font(.caption2)
                        .monospaced()
                        .lineLimit(nil)
                        .textSelection(.enabled)
                }
                if let ready = weles.admission_transport_ready {
                    HStack {
                        Text("Transport Ready:").font(.caption2)
                        Spacer()
                        Text(ready ? "✓ Yes" : "✗ No").foregroundColor(ready ? .green : .orange)
                    }
                }
                if let binding = weles.account_binding {
                    Text("Account: \(binding)")
                        .font(.caption2)
                        .lineLimit(nil)
                        .textSelection(.enabled)
                }
            }
        }
    }
    
    @ViewBuilder
    private func checkDetailsView(_ idx: Int, _ check: CrawlOperation.CrawlCatalog.PreflightDiagnostic.Check) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack {
                Text("Check \(idx + 1):").fontWeight(.semibold)
                Spacer()
                Text(check.ready ?? false ? "✓ Ready" : "✗ Not Ready")
                    .foregroundColor(check.ready ?? false ? .green : .orange)
            }
            if let cmd = check.command {
                Text("Command: \(cmd.joined(separator: " "))")
                    .monospaced()
                    .lineLimit(nil)
                    .textSelection(.enabled)
            }
            if let stdout = check.stdout {
                Text("stdout: \(stdout)").foregroundColor(.secondary).lineLimit(nil).textSelection(.enabled)
            }
            if let stderr = check.stderr {
                Text("stderr: \(stderr)").foregroundColor(.red).lineLimit(nil).textSelection(.enabled)
            }
            if let error = check.error {
                Text("error: \(error)").foregroundColor(.red).lineLimit(nil).textSelection(.enabled)
            }
        }
        .font(.caption2)
        .padding(.vertical, 2)
    }
    
    @ViewBuilder
    private func recordPreflightDetailsView(_ rc: CrawlOperation.CrawlCatalog.PreflightDiagnostic.RecordPreflightCheck) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack {
                VStack(alignment: .leading, spacing: 1) {
                    Text(rc.record ?? "unknown").font(.caption).fontWeight(.semibold).monospaced().textSelection(.enabled)
                    if let name = rc.name {
                        Text(name).font(.caption2).foregroundColor(.secondary)
                    }
                }
                Spacer()
                Text(rc.ready ?? false ? "✓ Ready" : "✗ Not Ready")
                    .font(.caption2)
                    .foregroundColor(rc.ready ?? false ? .green : .orange)
            }
            
            if let binding = rc.account_binding {
                Text("Account: \(binding)").font(.caption2).lineLimit(nil).textSelection(.enabled)
            }
            if let runtime = rc.required_runtime_product {
                Text("Runtime: \(runtime)").font(.caption2).lineLimit(nil).textSelection(.enabled)
            }
            if let diag = rc.diagnostic {
                Text("Diagnostic: \(diag)").font(.caption2).monospaced().lineLimit(nil).textSelection(.enabled)
            }
            
            if let checks = rc.checks, !checks.isEmpty {
                ForEach(Array(checks.enumerated()), id: \.offset) { idx, check in
                    VStack(alignment: .leading, spacing: 1) {
                        HStack {
                            Text("Check \(idx + 1)").font(.caption2).fontWeight(.semibold)
                            Spacer()
                            Text(check.ready ?? false ? "✓" : "✗")
                                .foregroundColor(check.ready ?? false ? .green : .orange)
                        }
                        if let cmd = check.command {
                            Text("Command: \(cmd.joined(separator: " "))").monospaced().lineLimit(nil).textSelection(.enabled)
                        }
                        if let stdout = check.stdout {
                            Text("stdout: \(stdout)").foregroundColor(.secondary).lineLimit(nil).textSelection(.enabled)
                        }
                        if let stderr = check.stderr {
                            Text("stderr: \(stderr)").foregroundColor(.red).lineLimit(nil).textSelection(.enabled)
                        }
                        if let error = check.error {
                            Text("error: \(error)").foregroundColor(.red).lineLimit(nil).textSelection(.enabled)
                        }
                    }
                    .font(.caption2)
                    .padding(.vertical, 1)
                }
            }
        }
        .font(.caption2)
        .padding(.vertical, 2)
    }
    
    @ViewBuilder
    private func recordsDisclosureView(_ records: [CrawlOperation.CrawlCatalog.CrawlRecord]) -> some View {
        DisclosureGroup("Records (\(records.count))") {
            VStack(alignment: .leading, spacing: 6) {
                ForEach(records, id: \.record) { record in
                    VStack(alignment: .leading, spacing: 2) {
                        HStack {
                            Text(record.record)
                                .font(.caption)
                                .monospaced()
                                .textSelection(.enabled)
                            Spacer()
                            Text(statusLabel(record.state))
                                .font(.caption2)
                                .fontWeight(.semibold)
                                .foregroundColor(stateColor(record.state))
                        }
                        
                        if record.states != nil || record.interactions != nil || record.media != nil {
                            HStack {
                                Text([
                                    record.states.map { "\($0) states" },
                                    record.interactions.map { "\($0) interactions" },
                                    record.media.map { "\($0) media" }
                                ].compactMap { $0 }.joined(separator: " · "))
                                    .font(.caption2)
                                    .foregroundColor(.secondary)
                                Spacer()
                            }
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
                                    .textSelection(.enabled)
                            }
                        }
                        
                        if let err = record.error {
                            HStack(alignment: .top, spacing: 4) {
                                Image(systemName: "xmark.circle")
                                    .font(.caption2)
                                    .foregroundColor(.red)
                                Text(err)
                                    .font(.caption2)
                                    .foregroundColor(.red)
                                    .lineLimit(nil)
                                    .textSelection(.enabled)
                            }
                        }
                    }
                    .padding(.vertical, 2)
                }
            }
        }
    }
    
    @ViewBuilder
    private func summaryView(_ counts: [String: Int]) -> some View {
        let catalogCounts = counts.filter { $0.key.hasPrefix("catalog_") }
        let recordCounts = counts.filter { $0.key.hasPrefix("record_") }
        
        if !catalogCounts.isEmpty {
            Text("Catalogs").fontWeight(.semibold).font(.caption)
            ForEach(catalogCounts.sorted(by: { $0.key < $1.key }), id: \.key) { key, value in
                HStack {
                    Text(countLabel(key))
                    Spacer()
                    Text("\(value)").fontWeight(.semibold)
                }
                .font(.caption)
            }
        }
        
        if !catalogCounts.isEmpty && !recordCounts.isEmpty {
            Divider()
        }
        
        if !recordCounts.isEmpty {
            Text("Records").fontWeight(.semibold).font(.caption)
            ForEach(recordCounts.sorted(by: { $0.key < $1.key }), id: \.key) { key, value in
                HStack {
                    Text(countLabel(key))
                    Spacer()
                    Text("\(value)").fontWeight(.semibold)
                }
                .font(.caption)
            }
        }
    }
    
    @ViewBuilder
    private func actionButtonsView(_ op: CrawlOperation) -> some View {
        HStack(spacing: 12) {
            if isRunning(op) {
                Button(action: {
                    model.checkCrawlStatus()
                }) {
                    HStack {
                        Image(systemName: "arrow.clockwise")
                        Text("Refresh")
                    }
                    .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
            }
            
            Button(action: { model.resetCrawl() }) {
                HStack {
                    Image(systemName: "arrow.counterclockwise")
                    Text("New Crawl")
                }
                .frame(maxWidth: .infinity)
            }
            .buttonStyle(.bordered)
            
            if shouldShowResume(op) {
                Button(action: { model.resumeCrawl() }) {
                    HStack {
                        Image(systemName: "play.circle")
                        Text("Resume")
                    }
                    .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
            }
            
            if shouldShowImport(op) {
                Button(action: { model.importCrawlResults() }) {
                    HStack {
                        Image(systemName: "arrow.down.doc")
                        Text("Import")
                    }
                    .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
            }
        }
    }
    
    @ViewBuilder
    private func failedFormView(_ error: String) -> some View {
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
    
    // MARK: - Helpers
    
    private func isRunning(_ op: CrawlOperation) -> Bool {
        guard let state = op.state else { return false }
        let s = state.lowercased()
        return ["queued", "running", "pending_review"].contains(s)
    }
    
    private func shouldShowResume(_ op: CrawlOperation) -> Bool {
        guard let state = op.state else { return false }
        let s = state.lowercased()
        return ["failed", "cancelled", "partial", "preflight_failed", "submission_failed", "lost"].contains(s)
    }
    
    private func shouldShowImport(_ op: CrawlOperation) -> Bool {
        guard let state = op.state else { return false }
        let s = state.lowercased()
        
        // Always available for completed/uploaded
        if ["completed", "uploaded"].contains(s) {
            return true
        }
        
        // For partial/failed/lost, check if there are importable records or artifacts
        if ["partial", "failed", "lost", "cancelled", "submission_failed"].contains(s) {
            if let catalogs = op.catalogs {
                for catalog in catalogs {
                    // Check for artifact_uri or output_uri
                    if catalog.artifact_uri != nil || catalog.output_uri != nil {
                        return true
                    }
                    
                    // Check for records with importable states
                    if let records = catalog.records {
                        for record in records {
                            let rs = record.state.lowercased()
                            if ["completed", "uploaded", "partial", "imported"].contains(rs) {
                                return true
                            }
                        }
                    }
                }
            }
        }
        
        return false
    }
    
    private func stateColor(_ state: String) -> Color {
        let s = state.lowercased()
        switch s {
        case "completed", "imported", "uploaded":
            return .green
        case "queued", "running", "pending_review":
            return .gray
        default:
            return .red
        }
    }
    
    private func statusLabel(_ state: String) -> String {
        let s = state.lowercased()
        switch s {
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
    
    private func countLabel(_ key: String) -> String {
        let label = key.hasPrefix("record_") ? String(key.dropFirst(7)) :
                   key.hasPrefix("catalog_") ? String(key.dropFirst(8)) : key
        return "• " + label.capitalized
    }
}

#Preview {
    CrawlersView()
        .environment(AppModel())
}
