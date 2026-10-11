import Foundation

/// The parsed end of one backend exchange: the operation's display name,
/// its outcome, the output it produced, and the refusal sentence when it
/// failed. No command line ever appears here.
struct SpisOutcome: Equatable, Sendable {
    /// User-language name of the operation, e.g. "Add record".
    let operation: String
    /// 0 on success; mirrors the exit code the operation would have had.
    let status: Int
    /// Everything the operation printed, in the backend's own order.
    let output: String
    /// The product's own refusal sentence, when the operation failed.
    let refusal: String?

    var succeeded: Bool { status == 0 }
}

/// The read-only operations the browse surface offers against the corpus.
enum SpisOperation: String, CaseIterable, Identifiable, Sendable {
    case catalogsCheck = "catalogs-check"
    case drift
    case verify
    case captureDryRun = "capture-dry-run"

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .catalogsCheck: return "Consistency check"
        case .drift: return "Upstream drift report"
        case .verify: return "Verify stored evidence"
        case .captureDryRun: return "Preview changes"
        }
    }

    var summary: String {
        switch self {
        case .catalogsCheck: return "validates the index against every record"
        case .drift: return "reports upstream README and URL drift"
        case .verify: return "checks saved results"
        case .captureDryRun: return "previews changes without saving them"
        }
    }
}

/// HTTP/JSON client for the local Spis backend. Every operation POSTs and
/// streams NDJSON — each log event is operation output in the backend's own
/// order, and the single result event carries the status and, on failure,
/// the product's refusal sentence verbatim.
struct SpisClient: Sendable {
    let baseURL: URL

    // MARK: - Read-only operations

    func run(_ operation: SpisOperation, catalog: String? = nil) async throws -> SpisOutcome {
        var body: [String: Any] = [:]
        if operation == .captureDryRun {
            body["catalog"] = catalog ?? ""
        }
        return try await post(operation.rawValue, operation: operation.displayName, body: body)
    }

    // MARK: - Docs corpus reads
    //
    // These answer with the JSON document the corpus view decodes; a refusal
    // arrives as a non-2xx envelope and is thrown with its sentence verbatim.

    func docsStatus() async throws -> Data {
        var request = URLRequest(
            url: baseURL.appendingPathComponent("v1").appendingPathComponent("docs-status"))
        request.httpMethod = "GET"
        return try await jsonDocument(request)
    }

    func docsSearch(query: String, site: String, limit: Int) async throws -> Data {
        try await jsonDocument(
            postRequest(
                "docs-search",
                body: [
                    "query": query,
                    "site": site,
                    "limit": limit,
                ]))
    }

    func docsShow(site: String, url: String) async throws -> Data {
        try await jsonDocument(
            postRequest(
                "docs-show",
                body: [
                    "site": site,
                    "url": url,
                ]))
    }

    // MARK: - Corpus adoption

    func adoptCorpus(at path: String) async throws -> SpisOutcome {
        try await post(
            "corpus-adopt",
            operation: "Adopt corpus",
            body: ["path": path]
        )
    }

    // MARK: - Manage operations

    func addCatalog(slug: String, title: String, description: String) async throws -> SpisOutcome {
        try await post(
            "catalog-add", operation: "Add product type",
            body: [
                "slug": slug,
                "title": title,
                "description": description,
            ])
    }

    /// Empty fields are left unchanged; `rename` is the new slug.
    func editCatalog(slug: String, title: String, description: String, rename: String) async throws
        -> SpisOutcome
    {
        try await post(
            "catalog-edit", operation: "Edit product type",
            body: [
                "slug": slug,
                "title": title,
                "description": description,
                "rename": rename,
            ])
    }

    func removeCatalog(slug: String, force: Bool) async throws -> SpisOutcome {
        try await post(
            "catalog-remove", operation: "Remove product type",
            body: [
                "slug": slug,
                "force": force,
            ])
    }

    func addReference(
        slug: String,
        name: String,
        sourceURL: String,
        category: String,
        selectionNote: String,
        visual: String
    ) async throws -> SpisOutcome {
        try await post(
            "reference-add", operation: "Add record",
            body: [
                "slug": slug,
                "name": name,
                "sourceUrl": sourceURL,
                "category": category,
                "selectionNote": selectionNote,
                "visual": visual,
            ])
    }

    func editReference(slug: String, number: Int, fields: [String: String]) async throws
        -> SpisOutcome
    {
        var body: [String: Any] = fields
        body["slug"] = slug
        body["number"] = number
        return try await post("reference-edit", operation: "Edit record", body: body)
    }

    func removeReference(slug: String, number: Int) async throws -> SpisOutcome {
        try await post(
            "reference-remove", operation: "Remove record",
            body: [
                "slug": slug,
                "number": number,
                "force": true,
            ])
    }

    // MARK: - Transport

    private func postRequest(_ endpoint: String, body: [String: Any]) throws -> URLRequest {
        var request = URLRequest(
            url: baseURL.appendingPathComponent("v1").appendingPathComponent(endpoint))
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        return request
    }

    private func jsonDocument(_ request: URLRequest) async throws -> Data {
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse else { throw SpisClientError.notHTTP }
        guard (200...299).contains(http.statusCode) else {
            throw SpisClientError.refusal(Self.refusalSentence(status: http.statusCode, body: data))
        }
        return data
    }

    private func post(
        _ endpoint: String,
        operation: String,
        body: [String: Any]
    ) async throws -> SpisOutcome {
        let (bytes, response) = try await URLSession.shared.bytes(
            for: try postRequest(endpoint, body: body))
        guard let http = response as? HTTPURLResponse else { throw SpisClientError.notHTTP }

        // A non-2xx before the stream starts is the error envelope.
        guard (200...299).contains(http.statusCode) else {
            var data = Data()
            for try await line in bytes.lines {
                data.append(contentsOf: line.utf8)
                data.append(UInt8(ascii: "\n"))
            }
            return SpisOutcome(
                operation: operation,
                status: 1,
                output: "",
                refusal: Self.refusalSentence(status: http.statusCode, body: data)
            )
        }

        var output = ""
        var resultStatus: Int?
        var resultObject: [String: Any]?
        for try await line in bytes.lines {
            guard !line.isEmpty else { continue }
            let (type, event) = try Self.streamEvent(line)
            switch type {
            case "log":
                let chunk = event["chunk"] as? String ?? ""
                output += chunk
            case "result":
                resultStatus = event["status"] as? Int
                resultObject = event["json"] as? [String: Any]
            default:
                continue
            }
        }
        guard let status = resultStatus else { throw SpisClientError.streamClosedEarly }

        let refusal: String?
        if status == 0 {
            refusal = nil
        } else if let sentence = resultObject?["error"] as? String, !sentence.isEmpty {
            refusal = sentence
        } else {
            refusal = "The operation failed. Review the output and try again."
        }
        return SpisOutcome(
            operation: operation,
            status: status,
            output: output.trimmingCharacters(in: .whitespacesAndNewlines),
            refusal: refusal
        )
    }

}
