import SwiftUI
import WisentDesignSystem
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
    /// The per-corpus page bound, and what this site could not fit inside it.
    ///
    /// Four sites in this family declare more in-scope pages than one corpus
    /// holds — Google Cloud 216,092, .NET 201,460, Azure 201,009, MDN 54,594
    /// against a 50,000-page bound — and one site is one corpus, so the
    /// remainder cannot be delivered by that record at all. Without these
    /// three numbers on screen those four read as ordinary failures instead
    /// of a capacity decision somebody has to make.
    let corpusBound: Int?
    let pagesOutsideCorpus: Int?
    let pagesOutsideCorpusExact: Bool?
    let retrievalStatus: String?

    var id: String { slug }

    enum CodingKeys: String, CodingKey {
        case slug, name, category, seen, noise, done
        case sourceURL = "source_url"
        case inventoryURLCount = "inventory_url_count"
        case cumulativeOK = "cumulative_ok"
        case corpusBound = "corpus_bound"
        case pagesOutsideCorpus = "pages_outside_corpus"
        case pagesOutsideCorpusExact = "pages_outside_corpus_exact"
        case retrievalStatus = "retrieval_status"
    }

    /// Fraction of the sitemap inventory that has been fetched at least once.
    var progress: Double {
        guard inventoryURLCount > 0 else { return 0 }
        return min(1, Double(seen) / Double(inventoryURLCount))
    }

    /// This site declares more in-scope pages than one corpus can hold.
    ///
    /// True from the declared inventory alone, before any attempt: the count
    /// of what was actually excluded arrives only once a run has measured it,
    /// and an operator deciding where to place work needs to know beforehand.
    var exceedsCorpusBound: Bool {
        guard let bound = corpusBound, bound > 0 else { return false }
        return inventoryURLCount > bound
    }

    /// `true` once a run has ended in the named over-capacity state.
    var overCapacity: Bool { retrievalStatus == "retrieval_over_capacity" }

    /// The remainder as a sentence, or `nil` when nothing is outside.
    var outsideCorpusSummary: String? {
        guard let bound = corpusBound else { return nil }
        let measured = pagesOutsideCorpus ?? 0
        if measured > 0 {
            let qualifier = pagesOutsideCorpusExact == false ? "at least " : ""
            return "\(qualifier)\(measured) pages outside this corpus (bound \(bound))"
        }
        if exceedsCorpusBound {
            return "declares \(inventoryURLCount) pages against a \(bound)-page corpus bound; "
                + "no attempt has measured the remainder yet"
        }
        return nil
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
        progressText = "Preparing…"
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
            progressText = "Searching \(site.name)…"
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
        progressText = Task.isCancelled ? "" : "Search complete"
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
                    "Documentation unavailable",
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
                // Inside a scroll view, like the list it stands in for: the
                // skeleton's own bars measure their nearest scrolling
                // container, and with none they would measure the window.
                ScrollView {
                    WisentSkeletonList(rows: 8, lines: 2, media: false, label: "Loading sites")
                        .padding(12)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
                .navigationSplitViewColumnWidth(min: 240, ideal: 280)
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
                                    .help("Complete")
                            } else if site.overCapacity || site.exceedsCorpusBound {
                                // Not a failure mark. This site is as complete
                                // as one corpus can be, and the rest is a
                                // capacity decision rather than a fault.
                                Image(systemName: "tray.full")
                                    .foregroundStyle(.orange)
                                    .help("Over the corpus bound: this site declares more pages than one corpus holds")
                            }
                        }
                        Text("\(site.cumulativeOK) available · \(site.inventoryURLCount) total")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        if let summary = site.outsideCorpusSummary {
                            Text(summary)
                                .font(.caption2)
                                .foregroundStyle(.orange)
                                .textSelection(.enabled)
                                .lineLimit(nil)
                        }
                        if site.overCapacity {
                            Text("retrieval_over_capacity")
                                .font(.caption2.monospaced())
                                .foregroundStyle(.orange)
                        }
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
            // A refresh of a list already on screen replaces nothing, so it
            // stays a badge and the rows underneath stay put. It is out of the
            // first read, where the skeleton list above is the region's one
            // announcement.
            if model.sitesLoading && !model.sites.isEmpty {
                HStack(spacing: 6) {
                    ProgressView()
                        .controlSize(.small)
                    Text("Refreshing")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .fixedSize()
                .padding(6)
                .accessibilityElement(children: .ignore)
                .accessibilityLabel("Refreshing sites")
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
                        // A scan in flight inside a text field: too small for a
                        // panel, and impersonating nothing, so it is the plain
                        // spinner it describes. The results pane below carries
                        // the region's progress report.
                        ProgressView()
                            .controlSize(.small)
                            .accessibilityLabel("Searching")
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
                        Text("\(model.hits.count) result\(model.hits.count == 1 ? "" : "s")")
                            .font(.caption)
                            .monospacedDigit()
                            .foregroundStyle(.secondary)
                    }
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                }

                if model.hits.isEmpty {
                    Group {
                        if model.searching {
                            // A scan already in flight, not content being read:
                            // it has no unloaded target to impersonate, so it
                            // reports its real status.
                            WisentProgressPanel(
                                title: "Searching",
                                detail: "Scanning the documentation corpus site by site."
                            )
                            .padding(20)
                        } else {
                            ContentUnavailableView(
                                "No results yet",
                                systemImage: "text.magnifyingglass",
                                description: Text("Enter at least 2 characters to search.")
                            )
                        }
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
                // The same three zones the loaded page draws — header, rule,
                // scrolling body — so nothing moves when the text lands, and
                // so the body's bars measure the scroll view rather than the
                // window.
                VStack(spacing: 0) {
                    VStack(alignment: .leading, spacing: 6) {
                        WisentSkeleton(.heading, width: 280, height: 20)
                        WisentSkeleton(.line, width: 220)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(16)

                    Divider()

                    ScrollView {
                        WisentSkeletonText(lines: 9, label: "Loading page")
                            .padding(20)
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
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
                    description: Text("No readable text is available for \(hit.url).")
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
