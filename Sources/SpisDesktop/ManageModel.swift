import Foundation

/// One product-type entry decoded from the generated `example-catalogs.json`.
struct TypeEntry: Identifiable, Decodable, Hashable {
    let slug: String
    let title: String
    let description: String
    let count: Int
    let scaffolded: Bool?

    var id: String { slug }
}

struct ReferenceEntry: Identifiable, Decodable, Hashable {
    let index: Int
    let name: String
    let path: String
    let evidenceStatus: String
    let evidenceGapCount: Int

    enum CodingKeys: String, CodingKey {
        case index, name, path
        case evidenceStatus = "evidence_status"
        case evidenceGapCount = "evidence_gap_count"
    }

    var id: String { path }
    var number: Int { index }
}

@MainActor
@Observable
final class ManageModel {
    let repository = CorpusRepository()

    var types: [TypeEntry] = []
    var references: [ReferenceEntry] = []
    var selectedCatalogSlug: String?
    var output: ReferenceCLI.Result?
    var running = false
    var statusText = ""

    func reloadTypes() {
        guard let root = repository.locate(),
              let data = try? Data(contentsOf: root.appendingPathComponent("example-catalogs.json")),
              let index = try? JSONDecoder().decode(CatalogIndex.self, from: data)
        else { return }
        types = index.catalogs.map { entry in
            TypeEntry(
                slug: entry.slug,
                title: entry.title,
                description: entry.description,
                count: entry.count,
                scaffolded: nil
            )
        }
    }

    func loadReferences(for slug: String) {
        guard let root = repository.locate() else { return }
        let url = root
            .appendingPathComponent(slug)
            .appendingPathComponent("references.json")
        struct Index: Decodable {
            let referenceCount: Int
            let references: [ReferenceEntry]
            enum CodingKeys: String, CodingKey {
                case referenceCount = "reference_count"
                case references
            }
        }
        guard let data = try? Data(contentsOf: url),
              let decoded = try? JSONDecoder().decode(Index.self, from: data)
        else {
            references = []
            return
        }
        selectedCatalogSlug = slug
        references = decoded.references
    }

    /// Runs a mutating CLI command, then refreshes local state.
    func run(_ arguments: [String]) async {
        guard let root = repository.locate() else { return }
        running = true
        statusText = "spis " + arguments.joined(separator: " ")
        let result = await Task.detached(priority: .userInitiated) {
            ReferenceCLI.run(root: root, arguments: arguments)
        }.value
        output = result
        running = false
        if result.succeeded {
            if arguments.first == "type", arguments.count > 1, ["add", "edit", "remove"].contains(arguments[1]) {
                reloadTypes()
            }
            if let slug = selectedCatalogSlug {
                loadReferences(for: slug)
            }
        }
    }
}
