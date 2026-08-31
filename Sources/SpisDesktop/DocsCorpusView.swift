import SwiftUI
import WisentErrors

// MARK: - Decoding

/// One entry of `spis docs-corpus status` JSON output.
struct DocsSiteStatus: Identifiable, Decodable, Hashable {
    let slug: String
    let name: String
    let category: String
    let sourceURL: String
    let inventoryURLCount: Int
    let seen: Int
    let cumulativeOK: Int
    let noise: Int
    let done: Bool

    var id: String { slug }

    enum CodingKeys: String, CodingKey {
        case slug, name, category, seen, noise, done
        case sourceURL = "source_url"
        case inventoryURLCount = "inventory_url_count"
        case cumulativeOK = "cumulative_ok"
    }

    /// Fraction of the sitemap inventory that has been fetched at least once.
    var progress: Double {
        guard inventoryURLCount > 0 else { return 0 }
        return min(1, Double(seen) / Double(inventoryURLCount))
    }
}

/// One hit from `spis docs-corpus search`.
struct DocsSearchHit: Identifiable, Decodable, Hashable {
    let slug: String
    let site: String
    let url: String
    let title: String?
    let snippet: String?

    var id: String { url }
}

struct DocsSearchEnvelope: Decodable {
    let hits: [DocsSearchHit]
    let scanned: Int
}

/// A full page record from `spis docs-corpus show`. Field types in the corpus
/// vary (numeric vs string status/bytes), so decode leniently.
struct DocsPage {
    let url: String
    let title: String
    let text: String
    let detailRows: [(String, String)]
}

// MARK: - Model

@MainActor
@Observable
final class DocsCorpusModel {
    private let backend = SpisBackendProcess()

    // Site list / progress
    var sites: [DocsSiteStatus] = []
    var sitesLoading = false
    var loadError: String?

    // Streaming search
    var query = ""
    var searching = false
    var progressText = ""
    var hits: [DocsSearchHit] = []
    var scannedPages = 0
    var searchError: String?

    // Text reader
    var selectedHit: DocsSearchHit?
    var page: DocsPage?
    var pageLoading = false

    private var searchTask: Task<Void, Never>?
    private var pageTask: Task<Void, Never>?

    /// Hard result ceiling so a broad term cannot accumulate unbounded rows.
    private static let maxHits = 100
    private static let perSiteLimit = 25
    private static let minimumQueryLength = 2
    private static let debounceNanos: UInt64 = 350_000_000

    func loadSites() async {
        sitesLoading = true
        loadError = nil
        defer { sitesLoading = false }
        do {
            let base = try await backend.endpoint()
            let data = try await SpisClient(baseURL: base).docsStatus()
            sites = try JSONDecoder().decode([DocsSiteStatus].self, from: data)
                .sorted { $0.slug < $1.slug }
        } catch {
            loadError = error.localizedDescription
            let backendError = error as? SpisBackendError
            WisentFailureReporter.shared.report(
                failurePoint: backendError == nil ? "spis.docs" : "spis.backend-start",
                code: backendError.map { $0.isMissingInstall ? "config" : "infra_down" } ?? "unknown",
                service: "spis",
                detail: error.localizedDescription
            )
        }
    }

    /// Debounced streaming search: scans site by site, appending hits as each
    /// site completes. A new query cancels the previous scan.
    func queryChanged() {
        searchTask?.cancel()
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.count >= Self.minimumQueryLength else {
            hits = []
            scannedPages = 0
            searching = false
            progressText = ""
            searchError = nil
            return
        }
        searchTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: Self.debounceNanos)
            guard !Task.isCancelled else { return }
            await self?.runSearch(trimmed)
        }
    }

    private func runSearch(_ trimmed: String) async {
        searching = true
        searchError = nil
        hits = []
        scannedPages = 0
        progressText = "preparing…"
        defer { searching = false }

        let client: SpisClient
        do {
            client = SpisClient(baseURL: try await backend.endpoint())
        } catch {
            searchError = error.localizedDescription
            progressText = ""
            // Only the backend start can throw here: the search never ran.
            let backendError = error as? SpisBackendError
            WisentFailureReporter.shared.report(
                failurePoint: backendError == nil ? "spis.docs" : "spis.backend-start",
                code: backendError.map { $0.isMissingInstall ? "config" : "infra_down" } ?? "unknown",
                service: "spis",
                detail: error.localizedDescription
            )
            return
        }

        for site in sites {
            if Task.isCancelled { return }
            if hits.count >= Self.maxHits { break }
            let remaining = Self.maxHits - hits.count
            let limit = min(Self.perSiteLimit, remaining)
            progressText = "scanning \(site.name)…"
            do {
                let data = try await client.docsSearch(query: trimmed, site: site.slug, limit: limit)
                if Task.isCancelled { return }
                let envelope = try JSONDecoder().decode(DocsSearchEnvelope.self, from: data)
                scannedPages += envelope.scanned
                hits.append(contentsOf: envelope.hits)
            } catch {
                // One unreadable site should not sink the whole scan.
                continue
            }
        }
        progressText = Task.isCancelled ? "" : "done — \(hits.count) hit\(hits.count == 1 ? "" : "s") across \(sites.count) sites"
    }

    func select(_ hit: DocsSearchHit) {
        pageTask?.cancel()
        selectedHit = hit
        page = nil
        pageLoading = true
        pageTask = Task {
            let record = await fetchPage(slug: hit.slug, url: hit.url)
            guard !Task.isCancelled else { return }
            pageLoading = false
            page = record
        }
    }

    private func fetchPage(slug: String, url: String) async -> DocsPage? {
        let data: Data
        do {
            let base = try await backend.endpoint()
            data = try await SpisClient(baseURL: base).docsShow(site: slug, url: url)
        } catch {
            return nil
        }
        guard let object = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any]
        else { return nil }

        func string(_ key: String) -> String {
            switch object[key] {
            case let value as String: return value
            case let value as NSNumber: return value.stringValue
            default: return ""
            }
        }
        var rows: [(String, String)] = []
        for key in ["status", "quality", "bytes", "fetched_at", "lastmod"] where object[key] != nil {
            rows.append((key, string(key)))
        }
        return DocsPage(
            url: string("url"),
            title: string("title"),
            text: string("text"),
            detailRows: rows
        )
    }
}

// MARK: - Views

struct DocsCorpusView: View {
    @State private var model = DocsCorpusModel()

    var body: some View {
        NavigationSplitView {
            DocsSidebar()
        } detail: {
            if let error = model.loadError {
                ContentUnavailableView(
                    "Docs corpus unavailable",
                    systemImage: "questionmark.folder",
                    description: Text(error)
                )
            } else {
                DocsSearchPane()
                    .task { await model.loadSites() }
                    .onDisappear { model.cancelAll() }
            }
        }
        .environment(model)
    }
}

private extension DocsCorpusModel {
    func cancelAll() {
        searchTask?.cancel()
        pageTask?.cancel()
        searching = false
        pageLoading = false
    }
}

/// Sidebar: the 50-site list with crawl progress.
struct DocsSidebar: View {
    @Environment(DocsCorpusModel.self) private var model

    var body: some View {
        Group {
            if model.sites.isEmpty && model.sitesLoading {
                ProgressView("Loading sites…")
            } else {
                List(model.sites) { site in
                    VStack(alignment: .leading, spacing: 4) {
                        HStack {
                            Text(site.name)
                                .font(.body)
                                .lineLimit(1)
                            Spacer()
                            if site.done {
                                Image(systemName: "checkmark.circle.fill")
                                    .foregroundStyle(.green)
                                    .help("Inventory fully crawled")
                            }
                        }
                        Text("\(site.cumulativeOK) ok · \(site.seen) seen · \(site.inventoryURLCount) in inventory")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        ProgressView(value: site.progress)
                            .progressViewStyle(.linear)
                            .controlSize(.small)
                    }
                    .padding(.vertical, 2)
                }
                .listStyle(.sidebar)
                .navigationSplitViewColumnWidth(min: 240, ideal: 280)
            }
        }
        .refreshable { await model.loadSites() }
        .overlay(alignment: .bottom) {
            if model.sitesLoading {
                ProgressView()
                    .controlSize(.small)
                    .padding(6)
            }
        }
    }
}

/// Search field, live progress line, and the streaming hit list.
struct DocsSearchPane: View {
    @Environment(DocsCorpusModel.self) private var model

    var body: some View {
        @Bindable var model = model
        HSplitView {
            VStack(spacing: 0) {
                HStack {
                    Image(systemName: "magnifyingglass")
                        .foregroundStyle(.secondary)
                    TextField("Search full text (min 2 characters)", text: $model.query)
                        .textFieldStyle(.plain)
                        .font(.system(.body, design: .monospaced))
                        .onSubmit { model.queryChanged() }
                        .onChange(of: model.query) { _, _ in model.queryChanged() }
                    if model.searching {
                        ProgressView().controlSize(.small)
                    } else if !model.query.isEmpty {
                        Button {
                            model.query = ""
                            model.queryChanged()
                        } label: {
                            Image(systemName: "xmark.circle.fill")
                                .foregroundStyle(.secondary)
                        }
                        .buttonStyle(.plain)
                        .disabled(model.query.isEmpty)
                    }
                }
                .padding(8)

                Divider()

                if !model.progressText.isEmpty || model.scannedPages > 0 {
                    HStack(spacing: 8) {
                        Text(model.progressText)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                        Spacer()
                        Text("\(model.hits.count) hits · \(model.scannedPages.formatted()) pages scanned")
                            .font(.caption)
                            .monospacedDigit()
                            .foregroundStyle(.secondary)
                    }
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                }

                if model.hits.isEmpty {
                    VStack(spacing: 6) {
                        ContentUnavailableView(
                            model.searching ? "Searching…" : "No results yet",
                            systemImage: "text.magnifyingglass",
                            description: Text(model.searching
                                ? "Streaming through the corpus site by site."
                                : "Type a query to stream matches out of the full-text docs corpus.")
                        )
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    List(model.hits) { hit in
                        DocsHitRow(hit: hit, isSelected: model.selectedHit?.url == hit.url)
                            .contentShape(Rectangle())
                            .onTapGesture { model.select(hit) }
                    }
                    .listStyle(.plain)
                }
            }
            .frame(minWidth: 360, idealWidth: 440)

            DocsReaderPane()
                .frame(minWidth: 380)
        }
    }
}

struct DocsHitRow: View {
    let hit: DocsSearchHit
    let isSelected: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(hit.title?.isEmpty == false ? hit.title! : hit.url)
                .font(.body.weight(isSelected ? .semibold : .regular))
                .lineLimit(1)
            Text(hit.snippet ?? "")
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(2)
            HStack(spacing: 6) {
                Text(hit.site)
                    .font(.caption2)
                Text(hit.url)
                    .font(.caption2)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
            .foregroundStyle(.tertiary)
        }
        .padding(.vertical, 2)
        .background(isSelected ? Color.accentColor.opacity(0.12) : .clear)
    }
}

/// Full-text reader for the selected hit.
struct DocsReaderPane: View {
    @Environment(DocsCorpusModel.self) private var model

    var body: some View {
        Group {
            if model.pageLoading {
                ProgressView("Loading page…")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if let page = model.page {
                VStack(spacing: 0) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(page.title.isEmpty ? page.url : page.title)
                            .font(.title3.bold())
                            .lineLimit(2)
                        Text(page.url)
                            .font(.caption)
                            .foregroundStyle(.link)
                            .lineLimit(1)
                            .truncationMode(.middle)
                        HStack(spacing: 10) {
                            ForEach(page.detailRows, id: \.0) { key, value in
                                Text("\(key): \(value)")
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(16)

                    Divider()

                    ScrollView {
                        Text(page.text)
                            .font(.system(.body, design: .serif))
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(20)
                    }
                }
            } else if let hit = model.selectedHit {
                ContentUnavailableView(
                    "Could not load page",
                    systemImage: "exclamationmark.triangle",
                    description: Text("The corpus has no readable text for \(hit.url).")
                )
            } else {
                ContentUnavailableView(
                    "Select a result",
                    systemImage: "doc.text.magnifyingglass",
                    description: Text("Pick a search hit to read its extracted full text.")
                )
            }
        }
    }
}
