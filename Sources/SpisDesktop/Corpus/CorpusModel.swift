import Foundation

/// One catalog entry decoded from `example-catalogs.json`.
struct CatalogSummary: Identifiable, Decodable, Hashable {
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
    var id: String { slug }
    var readme: String { "\(slug)/README.md" }

    enum CodingKeys: String, CodingKey {
        case slug, title, description, count
        case imageCount = "image_count"
        case structureCount = "structure_count"
        case completeRecordCount = "complete_record_count"
        case partialRecordCount = "partial_record_count"
        case measuredProvenance = "measured_provenance"
        case source
    }
}

struct CatalogIndex: Decodable {
    let catalogs: [CatalogSummary]
}

/// The repository the app operates on.
struct CorpusRepository {
    /// nil in development means the checkout this app was built from.
    var root: URL?

    init(root: URL? = nil) {
        self.root = root ?? ProcessInfo.processInfo.environment["REFERENCE_ENGINE_ROOT"]
            .map { URL(fileURLWithPath: $0) }
    }

    private var configurationURL: URL {
        let environment = ProcessInfo.processInfo.environment
        let configurationRoot: URL
        if let xdg = environment["XDG_CONFIG_HOME"], !xdg.isEmpty {
            configurationRoot = URL(fileURLWithPath: xdg, isDirectory: true)
        } else {
            configurationRoot = FileManager.default.homeDirectoryForCurrentUser
                .appendingPathComponent(".config", isDirectory: true)
        }
        return configurationRoot
            .appendingPathComponent("spis", isDirectory: true)
            .appendingPathComponent("corpus.json")
    }

    private var configuredRoot: URL? {
        guard let data = try? Data(contentsOf: configurationURL),
              let document = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              document["schema"] as? String == "spis.corpus-location.v1",
              let path = document["root"] as? String else {
            return nil
        }
        return URL(fileURLWithPath: path, isDirectory: true)
    }

    func locate() -> URL? {
        if FileManager.default.fileExists(atPath: configurationURL.path) {
            return configuredRoot
        }
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

    /// Locate the installed Spis checkout that owns the loopback API. An
    /// adopted corpus is data, not an executable installation.
    func locateProductRoot() -> URL? {
        if let root, FileManager.default.fileExists(atPath: root.appendingPathComponent("bin/spis-serve").path) {
            return root
        }
        var url = URL(fileURLWithPath: CommandLine.arguments[0]).resolvingSymlinksInPath()
        for _ in 0...8 {
            url.deleteLastPathComponent()
            if FileManager.default.fileExists(atPath: url.appendingPathComponent("bin/spis-serve").path) {
                return url
            }
            let sibling = url.appendingPathComponent("spis")
            if FileManager.default.fileExists(atPath: sibling.appendingPathComponent("bin/spis-serve").path) {
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
