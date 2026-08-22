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
    let readme: String

    var id: String { slug }

    enum CodingKeys: String, CodingKey {
        case slug, title, description, count
        case imageCount = "image_count"
        case structureCount = "structure_count"
        case completeRecordCount = "complete_record_count"
        case partialRecordCount = "partial_record_count"
        case measuredProvenance = "measured_provenance"
        case source, readme
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

    func locate() -> URL? {
        if let root, FileManager.default.fileExists(atPath: root.path) { return root }
        // Walk up from the executable: build products live several levels deep.
        var url = URL(fileURLWithPath: CommandLine.arguments[0]).resolvingSymlinksInPath()
        for _ in 0...8 {
            url.deleteLastPathComponent()
            if FileManager.default.fileExists(atPath: url.appendingPathComponent("example-catalogs.json").path) {
                return url
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

/// Runs `bin/reference` subcommands and captures their output.
struct ReferenceCLI {
    struct Result: Equatable {
        let command: String
        let output: String
        let exitCode: Int32
        var succeeded: Bool { exitCode == 0 }
    }

    static func run(root: URL, arguments: [String]) -> Result {
        let joined = arguments.joined(separator: " ")
        let cli = root.appendingPathComponent("bin/reference").path
        guard FileManager.default.isExecutableFile(atPath: cli) else {
            return Result(command: joined, output: "missing \(cli)", exitCode: 1)
        }
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
        process.arguments = ["python3", cli] + arguments
        process.currentDirectoryURL = root
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = pipe
        do {
            try process.run()
            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            process.waitUntilExit()
            let text = String(data: data, encoding: .utf8) ?? "(undecodable output)"
            return Result(command: "reference " + joined, output: text, exitCode: process.terminationStatus)
        } catch {
            return Result(command: "reference " + joined, output: "\(error)", exitCode: 1)
        }
    }
}
