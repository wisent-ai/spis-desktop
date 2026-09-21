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

    var searchTask: Task<Void, Never>?
    var pageTask: Task<Void, Never>?

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

