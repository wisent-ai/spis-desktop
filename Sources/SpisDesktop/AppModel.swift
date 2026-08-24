import SwiftUI

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
            loadError = "No spis checkout was found on this Mac."
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
            loadError = "\(error)"
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
        } catch {
            runState = .finished(SpisOutcome(
                operation: operation.displayName,
                status: 1,
                output: "",
                refusal: error.localizedDescription
            ))
        }
    }
}
