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
        case finished(ReferenceCLI.Result)
    }

    var runState: RunState = .idle

    var loadError: String?

    func load() {
        guard let root = repository.locate() else {
            loadError = "No spis checkout found. Set REFERENCE_ENGINE_ROOT to the repository path."
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

    func run(_ arguments: [String]) async {
        guard let root else { return }
        runState = .running("reference " + arguments.joined(separator: " "))
        let rootForRun = root
        let result = await Task.detached(priority: .userInitiated) {
            ReferenceCLI.run(root: rootForRun, arguments: arguments)
        }.value
        runState = .finished(result)
    }
}
