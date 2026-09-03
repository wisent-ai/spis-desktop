import Foundation

/// One catalog entry decoded from `example-catalogs.json`.
struct CatalogSummary: Identifiable, Decodable, Hashable, Sendable {
    let slug: String
    let title: String
    let description: String
    let count: Int
    let imageCount: Int
    let structureCount: Int
    let completeRecordCount: Int
    let partialRecordCount: Int
    let measuredProvenance: [String: Int]
    let source: String
    /// The catalog's own page, when the index names one.
    ///
    /// Optional, and read from either spelling, because this is what made the
    /// whole application unusable: `generate-example-catalogs` writes
    /// `full_reference_source` and no `readme`, this model required `readme`,
    /// so decoding `example-catalogs.json` threw on a current corpus and every
    /// screen — Browse, Crawlers, Manage, Docs — came up with no catalogs and
    /// the first-run walkthrough said "Spis found no installed corpus to
    /// read". A required field the product does not emit is not a stricter
    /// contract; it is a surface that cannot open its own data.
    let readme: String?
    let fullReferenceSource: String?

    var id: String { slug }

    /// Whichever page the index names, for display.
    var catalogPage: String {
        readme ?? fullReferenceSource ?? "—"
    }

    enum CodingKeys: String, CodingKey {
        case slug, title, description, count
        case imageCount = "image_count"
        case structureCount = "structure_count"
        case completeRecordCount = "complete_record_count"
        case partialRecordCount = "partial_record_count"
        case measuredProvenance = "measured_provenance"
        case source, readme
        case fullReferenceSource = "full_reference_source"
    }
}

struct CatalogIndex: Decodable, Sendable {
    let catalogs: [CatalogSummary]
}

/// Why one corpus could not be opened, in words this surface can print.
enum CorpusLoadFailure: Error, Sendable {
    case notInstalled
    case unreadable(path: String, reason: String)

    var sentence: String {
        switch self {
        case .notInstalled:
            return "Spis is not installed. Install Spis, then try again."
        case let .unreadable(path, reason):
            // The system's own sentence, kept: "permission denied" and "no
            // such file" are different problems and only the reason
            // distinguishes them.
            return "Spis could not read its corpus at \(path). \(reason)"
        }
    }
}

/// The repository the app operates on.
struct CorpusRepository: Sendable {
    /// nil in development means the checkout this app was built from.
    var root: URL?

    init(root: URL? = nil) {
        self.root = root ?? ProcessInfo.processInfo.environment["REFERENCE_ENGINE_ROOT"]
            .map { URL(fileURLWithPath: $0) }
    }

    /// The root this app was told to use, named without touching the file
    /// system — the one thing that is still safe to say when a read of that
    /// directory does not come back.
    var declaredRoot: String? {
        root?.path
            ?? ProcessInfo.processInfo.environment["SPIS_ROOT"]
            ?? ProcessInfo.processInfo.environment["REFERENCE_ENGINE_ROOT"]
    }

    func locate() -> URL? {
        if let root, FileManager.default.fileExists(atPath: root.path) { return root }
        if let fromEnv = ProcessInfo.processInfo.environment["SPIS_ROOT"],
           FileManager.default.fileExists(atPath: fromEnv) {
            return URL(fileURLWithPath: fromEnv)
        }
        // Walk up from the executable: build products live several levels deep.
        var url = URL(fileURLWithPath: CommandLine.arguments[0]).resolvingSymlinksInPath()
        for _ in 0...8 {
            url.deleteLastPathComponent()
            if FileManager.default.fileExists(atPath: url.appendingPathComponent("example-catalogs.json").path) {
                return url
            }
            // Sibling checkout layout: <parent>/spis next to <parent>/spis-desktop.
            let sibling = url.appendingPathComponent("spis")
            if FileManager.default.fileExists(atPath: sibling.appendingPathComponent("example-catalogs.json").path) {
                return sibling
            }
        }
        return nil
    }

    func loadIndex(from root: URL) throws -> CatalogIndex {
        let url = root.appendingPathComponent("example-catalogs.json")
        let data = try Data(contentsOf: url)
        return try JSONDecoder().decode(CatalogIndex.self, from: data)
    }

    func contractText(from root: URL) -> String? {
        try? String(contentsOf: root.appendingPathComponent("full-reference-contract.md"), encoding: .utf8)
    }
}
