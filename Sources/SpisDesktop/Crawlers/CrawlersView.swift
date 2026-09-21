import SwiftUI
import WisentDesignSystem

struct CrawlersView: View {
    @Environment(AppModel.self) var model
    @State var refreshTimer: Timer?
    @State var existingRunId = ""

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
    func errorStateView(_ error: String) -> some View {
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
    func emptyStateView() -> some View {
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
    func mainStateView() -> some View {
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
    func loadingView(_ title: String, _ detail: String) -> some View {
        WisentProgressPanel(title: title, detail: detail)
            .padding()
    }
    
    @ViewBuilder
    func actionButtonsView(_ op: CrawlOperation) -> some View {
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
    func failedFormView(_ error: String) -> some View {
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
    
    func isRunning(_ op: CrawlOperation) -> Bool {
        guard let state = op.state else { return false }
        let s = state.lowercased()
        return ["queued", "running", "pending_review"].contains(s)
    }
    
    func shouldShowResume(_ op: CrawlOperation) -> Bool {
        guard let state = op.state else { return false }
        let s = state.lowercased()
        return ["failed", "cancelled", "partial", "preflight_failed", "submission_failed", "lost"].contains(s)
    }
    
    func shouldShowImport(_ op: CrawlOperation) -> Bool {
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
    
    func stateColor(_ state: String) -> Color {
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
    
    func statusLabel(_ state: String) -> String {
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
    
    func countLabel(_ key: String) -> String {
        let label = key.hasPrefix("record_") ? String(key.dropFirst(7)) :
                   key.hasPrefix("catalog_") ? String(key.dropFirst(8)) : key
        return "• " + label.capitalized
    }
}

#Preview {
    CrawlersView()
        .environment(AppModel())
}
