import SwiftUI
import WisentDesignSystem

// The forms the crawlers pane shows: loading an existing run, starting a
// new one, and the status of the operation that came back.
//
// Split out of `CrawlersView.swift`, which had grown past the
// three-hundred-line limit.

extension CrawlersView {
    @ViewBuilder
    func idleFormView() -> some View {
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
    func loadExistingSection() -> some View {
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
    func newCrawlSection() -> some View {
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
    
    func disableStart() -> Bool {
        if case .loading = model.crawlState { return true }
        return false
    }
    
    @ViewBuilder
    func completedFormView(_ op: CrawlOperation) -> some View {
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
    func operationStatusView(_ op: CrawlOperation) -> some View {
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
    
}
