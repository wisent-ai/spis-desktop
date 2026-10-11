import Foundation
import WisentErrors

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
    var output: SpisOutcome?
    var running = false
    var statusText = ""
    /// Why the catalog index or a catalog's references could not be read.
    /// An unreadable file used to leave the list empty with no word, the same
    /// as a corpus that holds no catalog.
    var loadError: String?

    /// The corpus root, or nil after recording why it cannot be located.
    private func locatedRoot() -> URL? {
        do {
            guard let root = try repository.locate() else {
                loadError = "Spis corpus location is unavailable."
                return nil
            }
            return root
        } catch {
            loadError = "Spis corpus location is invalid: \(error.localizedDescription)"
            return nil
        }
    }

    func reloadTypes() {
        guard let root = locatedRoot() else { return }
        let url = root.appendingPathComponent("example-catalogs.json")
        let index: CatalogIndex
        do {
            index = try JSONDecoder().decode(CatalogIndex.self, from: Data(contentsOf: url))
        } catch {
            loadError = "\(url.path) cannot be read: \(error.localizedDescription)"
            types = []
            return
        }
        loadError = nil
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
        guard let root = locatedRoot() else { return }
        let url =
            root
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
        let decoded: Index
        do {
            decoded = try JSONDecoder().decode(Index.self, from: Data(contentsOf: url))
        } catch {
            loadError = "\(url.path) cannot be read: \(error.localizedDescription)"
            references = []
            return
        }
        loadError = nil
        selectedCatalogSlug = slug
        references = decoded.references
    }

    private let backend = SpisBackendProcess()

    func addReference(
        slug: String,
        name: String,
        sourceURL: String,
        category: String,
        selectionNote: String,
        visual: String
    ) async {
        await perform(operation: "Add record") { client in
            try await client.addReference(
                slug: slug,
                name: name,
                sourceURL: sourceURL,
                category: category,
                selectionNote: selectionNote,
                visual: visual
            )
        }
    }

    func editReference(slug: String, number: Int, fields: [String: String]) async {
        await perform(operation: "Edit record") { client in
            try await client.editReference(slug: slug, number: number, fields: fields)
        }
    }

    func removeReference(slug: String, number: Int) async {
        await perform(operation: "Remove record") { client in
            try await client.removeReference(slug: slug, number: number)
        }
    }

    func addCatalog(slug: String, title: String, description: String) async {
        await perform(operation: "Add product type") { client in
            try await client.addCatalog(slug: slug, title: title, description: description)
        }
    }

    func editCatalog(slug: String, title: String, description: String, rename: String) async {
        await perform(operation: "Edit product type") { client in
            try await client.editCatalog(
                slug: slug, title: title, description: description, rename: rename)
        }
        if output?.succeeded == true, !rename.isEmpty {
            selectedCatalogSlug = nil
            references = []
        }
    }

    func removeCatalog(slug: String, force: Bool) async {
        await perform(operation: "Remove product type") { client in
            try await client.removeCatalog(slug: slug, force: force)
        }
        if output?.succeeded == true {
            selectedCatalogSlug = nil
            references = []
        }
    }

    /// Runs one mutating operation through the backend, then refreshes local
    /// state. Refusals surface with the product's own sentence, verbatim.
    private func perform(
        operation: String,
        _ request: (SpisClient) async throws -> SpisOutcome
    ) async {
        running = true
        statusText = operation
        defer { running = false }
        do {
            let base = try await backend.endpoint()
            let outcome = try await request(SpisClient(baseURL: base))
            output = outcome
            if outcome.succeeded {
                reloadTypes()
                if let slug = selectedCatalogSlug {
                    loadReferences(for: slug)
                }
            } else if let refusal = outcome.refusal {
                // The outcome panel's source: a refusal becomes user-visible
                // state here, so it reports here.
                WisentFailureReporter.shared.report(
                    failurePoint: "spis.manage",
                    code: "unknown",
                    service: "spis",
                    detail: refusal
                )
            }
        } catch {
            output = SpisOutcome(
                operation: operation,
                status: 1,
                output: "",
                refusal: error.localizedDescription
            )
            let backendError = error as? SpisBackendError
            WisentFailureReporter.shared.report(
                failurePoint: backendError == nil ? "spis.manage" : "spis.backend-start",
                code: backendError.map { $0.isMissingInstall ? "config" : "infra_down" }
                    ?? "unknown",
                service: "spis",
                detail: error.localizedDescription
            )
        }
    }
}
