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
            catalogs = index.catalogs.sorted { $0.slug < $1.slug }
            selectedCatalog = catalogs.first
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

    // Crawl operations use CLI Process execution (see CrawlClient.swift extension)

    var selectedCrawlerFamily: String?

    var crawlState: AppModel.CrawlState = .idle
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

    private func needsAdmissionUrl(for catalog: CatalogSummary) -> Bool {
        let slug = catalog.slug
        return ["web-app-examples", "dashboard-console-examples", "onboarding-auth-examples",
                "app-store-listing-examples", "design-system-examples", "report-evidence-examples",
                "pricing-page-examples", "landing-page-examples"].contains(slug)
    }

    func startCrawl() {
        guard let catalog = selectedCatalogForCrawl else { return }
        guard let host = crawlHost?.trimmingCharacters(in: .whitespaces), !host.isEmpty else { return }
        guard let root = root else { return }

        let record = crawlRecord?.trimmingCharacters(in: .whitespaces)
        let trimmedRecord = record?.isEmpty == true ? nil : record

        if needsAdmissionUrl(for: catalog) {
            guard let url = crawlAdmissionUrl?.trimmingCharacters(in: .whitespaces), !url.isEmpty else { return }
        }

        crawlState = .loading
        Task {
            do {
                let config = CrawlerStartConfig(
                    catalogs: [catalog.slug],
                    host: host,
                    record: trimmedRecord,
                    admissionUrl: crawlAdmissionUrl?.trimmingCharacters(in: .whitespaces)
                )
                let result = try await client.crawlStart(config: config, workingDirectory: root)
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

        crawlState = .loading
        Task {
            do {
                let record = crawlRecord?.trimmingCharacters(in: .whitespaces)
                let trimmedRecord = record?.isEmpty == true ? nil : record
                let result = try await client.crawlStatus(runId: runId, record: trimmedRecord, workingDirectory: root)
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
                let result = try await client.crawlResume(runId: runId, workingDirectory: root)
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
                let result = try await client.crawlImport(runId: runId, workingDirectory: root)
                crawlState = .completed(result)
            } catch {
                crawlState = .failed(error.localizedDescription)
            }
        }
    }
}
