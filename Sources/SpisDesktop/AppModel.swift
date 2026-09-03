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

    /// One corpus, read on a background thread and handed over whole.
    private struct LoadedCorpus: Sendable {
        let root: URL
        let catalogs: [CatalogSummary]
        let contract: String?
    }

    /// Reads the installed corpus WITHOUT blocking the interface thread, and
    /// names a read this process cannot complete instead of freezing on it.
    ///
    /// This used to be a synchronous `Data(contentsOf:)` called straight out
    /// of a view body. Measured on this machine: launched through
    /// LaunchServices with the corpus under a folder the process has no
    /// file-access grant for, the main thread sat in `open()` for as long as
    /// the app was alive — 100% of samples in `__open`, `tccd` re-asking
    /// about the folder every thirty seconds — and the window never drew
    /// again. A hidden application cannot present the system's own
    /// permission sheet, so there was nothing on screen at all: no reason, no
    /// retry, no name for the state. An unreadable directory is a fact this
    /// surface must state, so the read happens off this thread and a read the
    /// system does not answer becomes a sentence on a deadline.
    func load() async {
        loadError = nil
        let repository = self.repository
        let read = Task.detached(priority: .userInitiated) { () throws -> LoadedCorpus in
            guard let root = repository.locate() else {
                throw CorpusLoadFailure.notInstalled
            }
            do {
                let index = try repository.loadIndex(from: root)
                return LoadedCorpus(
                    root: root,
                    catalogs: index.catalogs,
                    contract: repository.contractText(from: root)
                )
            } catch {
                throw CorpusLoadFailure.unreadable(
                    path: root.appendingPathComponent("example-catalogs.json").path,
                    reason: error.localizedDescription
                )
            }
        }
        let settled: Result<LoadedCorpus, Error>? = await withTaskGroup(
            of: Result<LoadedCorpus, Error>?.self
        ) { group in
            group.addTask {
                do { return .success(try await read.value) } catch { return .failure(error) }
            }
            group.addTask {
                try? await Task.sleep(nanoseconds: Self.corpusReadDeadlineNanos)
                return nil
            }
            let first = await group.next() ?? nil
            group.cancelAll()
            return first
        }
        switch settled {
        case let .success(corpus):
            root = corpus.root
            catalogs = corpus.catalogs.sorted { $0.title < $1.title }
            selectedCatalog = catalogs.first
            selectedCatalogForCrawl = catalogs.first
            contractText = corpus.contract
            loadError = nil
        case let .failure(error as CorpusLoadFailure):
            loadError = error.sentence
        case let .failure(error):
            loadError = "Spis could not read its corpus. \(error.localizedDescription)"
        case nil:
            // The read did not come back. Whatever the system is doing with
            // it, this window is not going to wait in silence.
            let named = repository.declaredRoot ?? "the corpus directory"
            loadError = "Spis could not read its corpus at \(named): the system did not answer "
                + "a read of that directory within \(Int(Self.corpusReadDeadlineNanos / 1_000_000_000)) seconds. "
                + "A file-access grant this process does not have looks exactly like this from a "
                + "background launch. Grant Spis access to that folder, or point SPIS_ROOT at one it can read."
        }
    }

    /// How long a corpus read may take before this surface states that it did
    /// not come back.
    private static let corpusReadDeadlineNanos: UInt64 = 6_000_000_000

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
    
    // MARK: - Cancellation, with the reason that goes into the record

    var crawlCancelReason: String?

    /// The reason a cancellation was actually dispatched with, kept after the
    /// fact.
    ///
    /// `spis crawl cancel` requires `--reason` and publishes it immutably
    /// with the intent before anything is dispatched, so the reason is part of
    /// the record rather than decoration. A surface that took it and then
    /// dropped it would leave the operator unable to read back what they
    /// claimed.
    var lastCancellation: (runId: String, reason: String)?

    /// Why a cancellation was not attempted at all.
    var cancelRefusal: String?

    func cancelCrawl() {
        cancelRefusal = nil
        guard let root = root else { return }
        guard let runId = currentRunId else {
            cancelRefusal = "Load or start a run first: cancellation names one run id."
            return
        }
        let reason = (crawlCancelReason ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        guard !reason.isEmpty else {
            cancelRefusal = "Give the reason. It is published with the cancellation before "
                + "anything is dispatched and stays in the record, so this command will not "
                + "run without one."
            return
        }
        let record = crawlRecord?.trimmingCharacters(in: .whitespaces)
        let trimmedRecord = (record?.isEmpty ?? true) ? nil : record
        crawlState = .running(operation: "Cancelling")
        Task {
            do {
                let result = try await crawlClient.crawlCancel(
                    runId: runId,
                    record: trimmedRecord,
                    reason: reason,
                    workingDirectory: root
                )
                lastCancellation = (runId: runId, reason: reason)
                crawlState = .completed(result)
            } catch {
                crawlState = .failed(error.localizedDescription)
            }
        }
    }

    // MARK: - Runtime bindings

    var bindingsWelesTokenRef: String?
    var bindingsOrganizationRef: String?
    var bindingsOutputPath: String?

    enum BindingsState: Equatable {
        case idle
        case generating
        case wrote(String)
        case refused(String)
    }

    var bindingsState: BindingsState = .idle

    /// `spis crawl bindings generate`, which only the command line could run.
    func generateBindings() {
        guard let root = root else { return }
        let token = (bindingsWelesTokenRef ?? "").trimmingCharacters(in: .whitespaces)
        let organization = (bindingsOrganizationRef ?? "").trimmingCharacters(in: .whitespaces)
        guard !token.isEmpty, !organization.isEmpty else {
            bindingsState = .refused(
                "Both references are required, each as ITEM#FIELD: the Weles token and the "
                + "organization. The generated binding is typed and exact, so a missing half is "
                + "not a default to guess."
            )
            return
        }
        let output = (bindingsOutputPath ?? "").trimmingCharacters(in: .whitespaces)
        bindingsState = .generating
        Task {
            do {
                let document = try await crawlClient.generateBindings(
                    welesTokenRef: token,
                    organizationRef: organization,
                    output: output.isEmpty ? nil : output,
                    workingDirectory: root
                )
                bindingsState = .wrote(document)
            } catch {
                bindingsState = .refused(error.localizedDescription)
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
        crawlCancelReason = nil
        cancelRefusal = nil
        lastCancellation = nil
        bindingsState = .idle
    }
}
