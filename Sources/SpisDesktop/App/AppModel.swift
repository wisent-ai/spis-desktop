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
        let located: URL?
        do {
            located = try repository.locate()
        } catch {
            clear(
                because: "Spis corpus location is invalid: \(error.localizedDescription)")
            return
        }
        guard let root = located else {
            clear(
                because:
                    "Spis corpus location is unavailable. Adopt an existing canonical corpus, then try again."
            )
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
            clear(because: "Spis data could not be loaded: \(error.localizedDescription)")
        }
    }

    private func clear(because reason: String) {
        root = nil
        catalogs = []
        selectedCatalog = nil
        selectedCatalogForCrawl = nil
        contractText = nil
        loadError = reason
    }

    /// The native picker supplies only a directory URL. Validation and durable
    /// adoption run through Spis's loopback API and the product-owned `corpus`
    /// operation, never through a desktop copy of the importer.
    func adoptCorpus(at url: URL) async -> Bool {
        if case .running = runState { return false }
        runState = .running("Adopting corpus")
        do {
            let base = try await backend.endpoint()
            let outcome = try await SpisClient(baseURL: base).adoptCorpus(at: url.path)
            runState = .finished(outcome)
            if outcome.succeeded {
                load()
                return true
            }
            if let refusal = outcome.refusal {
                SpisFailure.reportRefusal(refusal, at: "spis.corpus-adopt")
            }
            return false
        } catch {
            runState = .finished(
                SpisOutcome(
                    operation: "Adopt corpus",
                    status: 1,
                    output: "",
                    refusal: error.localizedDescription
                ))
            SpisFailure.report(error, at: "spis.corpus-adopt")
            return false
        }
    }

    private let backend = SpisBackendProcess()

    /// Runs one read-only operation through the backend, then reports the
    /// outcome. The operation name is user language; no command line exists.
    func run(_ operation: SpisOperation) async {
        runState = .running(operation.displayName)
        do {
            let base = try await backend.endpoint()
            let outcome = try await SpisClient(baseURL: base).run(
                operation, catalog: selectedCatalog?.slug)
            runState = .finished(outcome)
            // The outcome panel's source: a refusal becomes user-visible
            // state here, so it reports here.
            if let refusal = outcome.refusal {
                SpisFailure.reportRefusal(refusal, at: "spis.browse")
            }
        } catch {
            runState = .finished(
                SpisOutcome(
                    operation: operation.displayName,
                    status: 1,
                    output: "",
                    refusal: error.localizedDescription
                ))
            SpisFailure.report(error, at: "spis.browse")
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
            case (.running(let op1), .running(let op2)):
                return op1 == op2
            case (.completed(let c1), .completed(let c2)):
                return c1.run_id == c2.run_id
            case (.failed(let e1), .failed(let e2)):
                return e1 == e2
            default:
                return false
            }
        }
    }

    func startCrawl() {
        guard let root = root else { return }

        let catalogsToUse = selectedCatalogForCrawl.map { [$0.slug] } ?? []

        let record = crawlRecord?.trimmingCharacters(in: .whitespaces)
        let trimmedRecord = record?.isEmpty == true ? nil : record
        let trimmedHost =
            crawlHost?.trimmingCharacters(in: .whitespaces).isEmpty == true
            ? nil : crawlHost?.trimmingCharacters(in: .whitespaces)
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
                let result = try await crawlClient.crawlStatus(
                    runId: runId, record: trimmedRecord, workingDirectory: root)
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
