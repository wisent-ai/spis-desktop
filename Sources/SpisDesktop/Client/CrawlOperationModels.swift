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
