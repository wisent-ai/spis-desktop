import Foundation

/// How many records of one catalog belong to one category, as
/// `spis generate-example-catalogs` counts them from the records themselves.
struct CategoryCount: Decodable, Hashable {
    let category: String
    let count: Int
}

/// One catalog entry decoded from `example-catalogs.json`.
struct CatalogSummary: Identifiable, Decodable, Hashable {
    let slug: String
    let title: String
    let description: String
    let count: Int
    let categories: [CategoryCount]
    let imageCount: Int
    let structureCount: Int
    let completeRecordCount: Int
    let partialRecordCount: Int
    let measuredProvenance: [String: Int]
    let source: String
    var id: String { slug }
    var readme: String { "\(slug)/README.md" }

    enum CodingKeys: String, CodingKey {
        case slug, title, description, count, categories
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
        self.root =
            root
            ?? ProcessInfo.processInfo.environment["REFERENCE_ENGINE_ROOT"]
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
        return
            configurationRoot
            .appendingPathComponent("spis", isDirectory: true)
            .appendingPathComponent("corpus.json")
    }

    /// The corpus root the configuration names. A configuration that cannot be
    /// read, is not JSON, has another schema or names no root fails with the
    /// file and the cause.
    private func configuredRoot() throws -> URL {
        let url = configurationURL
        let data: Data
        do {
            data = try Data(contentsOf: url)
        } catch {
            throw CorpusLocationError("\(url.path) cannot be read: \(error.localizedDescription)")
        }
        let parsed: Any
        do {
            parsed = try JSONSerialization.jsonObject(with: data)
        } catch {
            throw CorpusLocationError("\(url.path) is not JSON: \(error.localizedDescription)")
        }
        guard let document = parsed as? [String: Any] else {
            throw CorpusLocationError("\(url.path) is not a JSON object")
        }
        guard document["schema"] as? String == Self.locationSchema else {
            throw CorpusLocationError(
                "\(url.path) declares schema \(String(describing: document["schema"])), not \(Self.locationSchema)"
            )
        }
        guard let path = document["root"] as? String else {
            throw CorpusLocationError("\(url.path) names no root")
        }
        return URL(fileURLWithPath: path, isDirectory: true)
    }

    private static let locationSchema = "spis.corpus-location.v1"

    /// The corpus root, from explicit sources only: the location Spis core
    /// saved (`corpus.json`), `REFERENCE_ENGINE_ROOT`, then `SPIS_ROOT`. The
    /// app never walks the folders above itself looking for one: on macOS that
    /// reads whatever folder the app happens to sit in (Documents, Desktop,
    /// Downloads) and makes the system ask the person for access to it.
    func locate() throws -> URL? {
        if FileManager.default.fileExists(atPath: configurationURL.path) {
            return try configuredRoot()
        }
        if let root, FileManager.default.fileExists(atPath: root.path) { return root }
        if let fromEnv = ProcessInfo.processInfo.environment["SPIS_ROOT"],
            FileManager.default.fileExists(atPath: fromEnv)
        {
            return URL(fileURLWithPath: fromEnv)
        }
        return nil
    }

    /// The built `spis` executable of a checkout: the release build, else the
    /// debug build, the order a developer and an install produce them in.
    func spisExecutable(in root: URL) -> URL? {
        BuildProfile.allCases
            .map { root.appendingPathComponent($0.executablePath) }
            .first { FileManager.default.isExecutableFile(atPath: $0.path) }
    }

    /// The cargo profiles a `spis` executable is built under, release first.
    enum BuildProfile: CaseIterable {
        case release
        case debug

        var executablePath: String {
            switch self {
            case .release: "target/release/spis"
            case .debug: "target/debug/spis"
            }
        }
    }

    /// The Spis checkout `REFERENCE_ENGINE_ROOT` names, when it holds a built
    /// `spis`. An adopted corpus is data, not an executable installation, and
    /// the folders above this app are never searched (see `locate`).
    func locateProductRoot() -> URL? {
        if let root, spisExecutable(in: root) != nil {
            return root
        }
        return nil
    }

    func loadIndex(from root: URL) throws -> CatalogIndex {
        let url = root.appendingPathComponent("example-catalogs.json")
        let data = try Data(contentsOf: url)
        return try JSONDecoder().decode(CatalogIndex.self, from: data)
    }

    /// The corpus's reference contract, or nil when the corpus carries none. A
    /// contract that exists and cannot be read is the load's failure, never
    /// shown as a corpus without one.
    func contractText(from root: URL) throws -> String? {
        let url = root.appendingPathComponent("full-reference-contract.md")
        guard FileManager.default.fileExists(atPath: url.path) else { return nil }
        return try String(contentsOf: url, encoding: .utf8)
    }
}

/// Why the configured corpus location could not be used.
struct CorpusLocationError: LocalizedError {
    let reason: String
    init(_ reason: String) { self.reason = reason }
    var errorDescription: String? { reason }
}
