import Foundation

// MARK: - Crawl Operation JSON Schema (wisent.crawl-operation.v1)

/// One `wisent.crawl-host-preflight.v2` report, as `spis crawl preflight`
/// prints it.
///
/// The same document the crawl embeds per catalog, asked on its own. Before
/// this existed the graphical surface could only see a preflight AFTER a run
/// had been started and had already refused, so "can this host run this
/// family" was a question only the command line could ask — and the answer
/// arrived attached to a failed attempt. Every check keeps the host's own
/// words, because a refusal paraphrased by this side is how a missing
/// program and a probe this side spelled wrong become indistinguishable.
struct HostPreflightReport: Codable, Sendable {
    let schema: String?
    let catalog: String?
    let engine: String?
    let host: String?
    let ready: Bool?
    let checks: [PreflightCheck]?

    struct PreflightCheck: Codable, Sendable, Identifiable {
        let command: [String]?
        let ready: Bool?
        let stdout: String?
        let stderr: String?
        let error: String?

        var id: String { (command ?? []).joined(separator: " ") }

        /// The probe as an operator would type it.
        var spelling: String { (command ?? []).joined(separator: " ") }

        /// What the host said, unedited and unsummarised: its answer when the
        /// probe ran, its refusal when it did not.
        var hostWords: String {
            for candidate in [error, stderr, stdout] {
                let trimmed = candidate?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
                if !trimmed.isEmpty { return trimmed }
            }
            return ""
        }
    }

    /// Only the preconditions the host does not satisfy.
    var missing: [PreflightCheck] {
        (checks ?? []).filter { $0.ready != true }
    }
}

struct CrawlOperation: Codable, Sendable {
    let schema: String
    let operation: String
    let run_id: String?
    let state: String?
    let source_revision: String?
    let updated_at: String?
    let counts: [String: Int]?
    let catalogs: [CrawlCatalog]?

    struct CrawlCatalog: Codable, Sendable {
        let catalog: String
        let state: String
        let engine: String?
        let job_id: String?
        let artifact_uri: String?
        let output_uri: String?
        let error: String?
        let preflight: PreflightDiagnostic?
        let records: [CrawlRecord]?

        struct PreflightDiagnostic: Codable, Sendable {
            let schema: String?
            let catalog: String?
            let engine: String?
            let host: String?
            let ready: Bool?
            let checks: [Check]?
            let records: [RecordPreflightCheck]?
            let weles: WelesInfo?
            let no_permission_prompts_requested: Bool?
            
            struct Check: Codable, Sendable {
                let command: [String]?
                let ready: Bool?
                let stdout: String?
                let stderr: String?
                let error: String?
            }
            
            struct WelesInfo: Codable, Sendable {
                let admission_url: String?
                let admission_transport_ready: Bool?
                let account_binding: String?
            }
            
            struct RecordPreflightCheck: Codable, Sendable {
                let record: String?
                let name: String?
                let required_runtime_product: String?
                let account_binding: String?
                let ready: Bool?
                let checks: [Check]?
                let diagnostic: String?
            }
        }

        struct CrawlRecord: Codable, Sendable {
            let record: String
            let state: String
            let states: Int?
            let interactions: Int?
            let media: Int?
            let gaps: [String]?
            let error: String?
        }
    }

    var isTerminal: Bool {
        guard let state = state else { return false }
        let s = state.lowercased()
        return ["completed", "uploaded", "failed", "imported", "partial", "cancelled", "lost", "preflight_failed", "submission_failed"].contains(s)
    }

    var isError: Bool {
        guard let state = state else { return false }
        let s = state.lowercased()
        return ["failed", "partial", "cancelled", "lost", "preflight_failed", "submission_failed"].contains(s)
    }

    func countForState(_ state: String) -> Int {
        counts?[state] ?? 0
    }

    func totalRecords() -> Int {
        catalogs?.reduce(0) { $0 + ($1.records?.count ?? 0) } ?? 0
    }

    func totalCompleted() -> Int {
        counts?["record_completed"] ?? 0
    }

    func totalImported() -> Int {
        counts?["record_imported"] ?? 0
    }
}

// MARK: - Crawler Start Configuration

struct CrawlerStartConfig: Sendable {
    let catalogs: [String] // One or more catalog slugs
    let host: String? // Optional global host override
    var hostMappings: [String: String]? = nil // Optional ENGINE=TARGET or CATALOG=TARGET mappings
    let record: String? // Optional specific record
    let admissionUrl: String? // Optional admission-url override

    func buildArguments() -> [String] {
        var args = ["crawl", "start"]
        
        for catalog in catalogs {
            args.append("--catalog")
            args.append(catalog)
        }
        
        // Add host overrides: catalog-specific, engine-specific, or global
        if let mappings = hostMappings {
            for (scope, target) in mappings {
                args.append("--host")
                args.append("\(scope)=\(target)")
            }
        }
        if let globalHost = host {
            args.append("--host")
            args.append(globalHost)
        }
        
        if let record = record {
            args.append("--record")
            args.append(record)
        }
        
        if let url = admissionUrl {
            args.append("--admission-url")
            args.append(url)
        }
        
        return args
    }
}

// MARK: - Process Execution Result

struct ProcessResult: Sendable {
    let exitCode: Int32
    let stdout: String
    let stderr: String

    var succeeded: Bool { exitCode == 0 }
    var error: String? {
        guard !succeeded else { return nil }
        return stderr.isEmpty ? "Process exited with code \(exitCode)" : stderr
    }
}
