import Foundation

// MARK: - Crawl Operation JSON Schema (wisent.crawl-operation.v1)

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
        return ["completed", "failed", "imported"].contains(state)
    }

    var isError: Bool {
        guard let state = state else { return false }
        return ["failed", "submission_failed", "preflight_failed"].contains(state)
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
