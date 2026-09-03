import SwiftUI
import WisentErrors

@MainActor
@Observable
final class AppModel {
    let repository = CorpusRepository()

    var root: URL?
    var catalogs: [CatalogSummary] = []
    var selectedCatalog: CatalogSummary?
    var contractText: String?

    enum RunState: Equatable {
        case idle
        case running(String)
        case finished(SpisOutcome)
    }

    var runState: RunState = .idle

    var loadError: String?

    func load() {
        guard let root = repository.locate() else {
            loadError = "Spis is not installed. Install Spis, then try again."
            return
        }
        self.root = root
        do {
            let index = try repository.loadIndex(from: root)
            catalogs = index.catalogs.sorted { $0.title < $1.title }
            selectedCatalog = catalogs.first
            selectedCatalogForCrawl = catalogs.first
            contractText = repository.contractText(from: root)
            loadError = nil
        } catch {
            loadError = "Spis data could not be loaded. Try again."
        }
    }

    private let backend = SpisBackendProcess()

    /// Runs one read-only operation through the backend, then reports the
    /// outcome. The operation name is user language; no command line exists.
    func run(_ operation: SpisOperation) async {
        runState = .running(operation.displayName)
        do {
            let base = try await backend.endpoint()
            let outcome = try await SpisClient(baseURL: base).run(operation, catalog: selectedCatalog?.slug)
            runState = .finished(outcome)
            // The outcome panel's source: a refusal becomes user-visible
            // state here, so it reports here.
            if let refusal = outcome.refusal {
                WisentFailureReporter.shared.report(
                    failurePoint: "spis.browse",
                    code: "unknown",
                    service: "spis",
                    detail: refusal
                )
            }
        } catch {
            runState = .finished(SpisOutcome(
                operation: operation.displayName,
                status: 1,
                output: "",
                refusal: error.localizedDescription
            ))
            let backendError = error as? SpisBackendError
            WisentFailureReporter.shared.report(
                failurePoint: backendError == nil ? "spis.browse" : "spis.backend-start",
                code: backendError.map { $0.isMissingInstall ? "config" : "infra_down" } ?? "unknown",
                service: "spis",
                detail: error.localizedDescription
            )
        }
    }

    // MARK: - Crawl operations

    private let crawlClient = SpisCrawlClient()

    var crawlState: CrawlState = .idle
    var selectedCatalogForCrawl: CatalogSummary?
    var crawlRecord: String?
    var crawlHost: String?
    var crawlAdmissionUrl: String?
    var currentRunId: String?

    enum CrawlState: Equatable {
        case idle
        case loading
        case running(operation: String)
        case completed(CrawlOperation)
        case failed(String)

        static func == (lhs: CrawlState, rhs: CrawlState) -> Bool {
            switch (lhs, rhs) {
            case (.idle, .idle), (.loading, .loading):
                return true
            case let (.running(op1), .running(op2)):
                return op1 == op2
            case let (.completed(c1), .completed(c2)):
                return c1.run_id == c2.run_id
            case let (.failed(e1), .failed(e2)):
                return e1 == e2
            default:
                return false
            }
        }
    }

    /// The readiness question, asked on its own and answered before anything
    /// is claimed.
    ///
    /// Separate from `crawlState` on purpose: a preflight is not an attempt.
    /// A host that is not ready is a fact to read, not a run that failed, and
    /// collapsing the two is what left this surface unable to ask the
    /// question at all until a run had already been submitted.
    enum PreflightState: Equatable {
        case idle
        case checking(catalog: String, host: String)
        case answered(HostPreflightReport)
        case unavailable(String)

        static func == (lhs: PreflightState, rhs: PreflightState) -> Bool {
            switch (lhs, rhs) {
            case (.idle, .idle):
                return true
            case let (.checking(catalogLeft, hostLeft), .checking(catalogRight, hostRight)):
                return catalogLeft == catalogRight && hostLeft == hostRight
            case let (.answered(left), .answered(right)):
                return left.host == right.host
                    && left.catalog == right.catalog
                    && left.ready == right.ready
                    && (left.checks?.count ?? 0) == (right.checks?.count ?? 0)
            case let (.unavailable(left), .unavailable(right)):
                return left == right
            default:
                return false
            }
        }
    }

    var preflightState: PreflightState = .idle

    /// Ask one host about one family. Read-only; claims nothing.
    func checkHostReadiness() {
        guard let root = root else { return }
        guard let catalog = selectedCatalogForCrawl?.slug else {
            preflightState = .unavailable(
                "Choose one product family: readiness is a question about a family's worker, and every family requires different programs."
            )
            return
        }
        let host = (crawlHost ?? "").trimmingCharacters(in: .whitespaces)
        guard !host.isEmpty else {
            preflightState = .unavailable(
                "Name the host to ask. Readiness is a property of one machine, and Stado picks the host only once a run is submitted."
            )
            return
        }
        preflightState = .checking(catalog: catalog, host: host)
        Task {
            do {
                let report = try await crawlClient.crawlPreflight(
                    catalog: catalog,
                    host: host,
                    workingDirectory: root
                )
                preflightState = .answered(report)
            } catch {
                preflightState = .unavailable(error.localizedDescription)
            }
        }
    }

    func startCrawl() {
        guard let root = root else { return }
        
        let catalogsToUse = selectedCatalogForCrawl.map { [$0.slug] } ?? []
        
        let record = crawlRecord?.trimmingCharacters(in: .whitespaces)
        let trimmedRecord = record?.isEmpty == true ? nil : record
        let trimmedHost = crawlHost?.trimmingCharacters(in: .whitespaces).isEmpty == true ? nil : crawlHost?.trimmingCharacters(in: .whitespaces)
        let trimmedAdmissionUrl = crawlAdmissionUrl.flatMap { 
            let t = $0.trimmingCharacters(in: .whitespaces)
            return t.isEmpty ? nil : t
        }
        
        if selectedCatalogForCrawl == nil && trimmedRecord != nil {
            // Record not allowed when all catalogs selected
            return
        }

        crawlState = .loading
        Task {
            do {
                let result = try await crawlClient.crawlStart(
                    catalogs: catalogsToUse,
                    host: trimmedHost,
                    record: trimmedRecord,
                    admissionUrl: trimmedAdmissionUrl,
                    workingDirectory: root
                )
                currentRunId = result.run_id
                crawlState = .completed(result)
            } catch {
                crawlState = .failed(error.localizedDescription)
            }
        }
    }

    func checkCrawlStatus() {
        guard let runId = currentRunId else { return }
        guard let root = root else { return }

        crawlState = .running(operation: "Checking status")
        Task {
            do {
                let record = crawlRecord?.trimmingCharacters(in: .whitespaces)
                let trimmedRecord = record?.isEmpty == true ? nil : record
                let result = try await crawlClient.crawlStatus(runId: runId, record: trimmedRecord, workingDirectory: root)
                crawlState = .completed(result)
            } catch {
                crawlState = .failed(error.localizedDescription)
            }
        }
    }

    func resumeCrawl() {
        guard let runId = currentRunId else { return }
        guard let root = root else { return }

        crawlState = .running(operation: "Resuming")
        Task {
            do {
                let result = try await crawlClient.crawlResume(runId: runId, workingDirectory: root)
                crawlState = .completed(result)
            } catch {
                crawlState = .failed(error.localizedDescription)
            }
        }
    }

    func importCrawlResults() {
        guard let runId = currentRunId else { return }
        guard let root = root else { return }

        crawlState = .running(operation: "Importing")
        Task {
            do {
                let result = try await crawlClient.crawlImport(runId: runId, workingDirectory: root)
                crawlState = .completed(result)
            } catch {
                crawlState = .failed(error.localizedDescription)
            }
        }
    }
    
    func resetCrawl() {
        crawlState = .idle
        currentRunId = nil
        selectedCatalogForCrawl = catalogs.first
        crawlRecord = nil
        crawlHost = nil
        crawlAdmissionUrl = nil
    }
}
