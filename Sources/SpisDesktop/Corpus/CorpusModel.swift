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
        // Walk up from the executable: build products live several levels deep.
        for directory in executableAncestors() {
            if FileManager.default.fileExists(
                atPath: directory.appendingPathComponent("example-catalogs.json").path)
            {
                return directory
            }
            // Sibling checkout layout: <parent>/spis next to <parent>/spis-desktop.
            let sibling = directory.appendingPathComponent("spis")
            if FileManager.default.fileExists(
                atPath: sibling.appendingPathComponent("example-catalogs.json").path)
            {
                return sibling
            }
        }
        return nil
    }

    /// The directories above this app's executable, nearest first, up to the
    /// filesystem root; none when the process has no executable URL.
    private func executableAncestors() -> [URL] {
        guard var url = Bundle.main.executableURL?.resolvingSymlinksInPath() else { return [] }
        var ancestors: [URL] = []
        while url.path != "/" {
            url.deleteLastPathComponent()
            ancestors.append(url)
        }
        return ancestors
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

    /// Locate the installed Spis checkout that owns the loopback API: the
    /// configured root, else a directory above this app (or its `spis`
    /// sibling) that holds a built `spis`. An adopted corpus is data, not an
    /// executable installation.
    func locateProductRoot() -> URL? {
        if let root, spisExecutable(in: root) != nil {
            return root
        }
        for directory in executableAncestors() {
            if spisExecutable(in: directory) != nil {
                return directory
            }
            let sibling = directory.appendingPathComponent("spis")
            if spisExecutable(in: sibling) != nil {
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
