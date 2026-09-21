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

    func removeReference(slug: String, number: Int) async {
        await perform(operation: "Remove record") { client in
            try await client.removeReference(slug: slug, number: number)
        }
    }

    func deriveGuidelines(slug: String) async {
        await perform(operation: "Derive guidelines draft") { client in
            try await client.deriveGuidelines(slug: slug)
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
                code: backendError.map { $0.isMissingInstall ? "config" : "infra_down" } ?? "unknown",
                service: "spis",
                detail: error.localizedDescription
            )
        }
    }
}
