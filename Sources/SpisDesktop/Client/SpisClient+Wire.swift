import Foundation

enum SpisClientError: LocalizedError {
    case notHTTP
    case streamClosedEarly
    case refusal(String)
    /// A stream line that is not a JSON event with a type.
    case unreadableEvent(String)

    var errorDescription: String? {
        switch self {
        case .notHTTP:
            return "Spis returned an unreadable response. Try again."
        case .streamClosedEarly:
            return "The operation ended unexpectedly. Try again."
        case .refusal(let sentence):
            return sentence
        case .unreadableEvent(let line):
            return "Spis sent an operation event that is not a JSON event: \(line)"
        }
    }
}

extension SpisClient {
    /// The sentence for a refused request: the backend's own `error` when its
    /// JSON envelope carries one, otherwise the status and the body it sent.
    /// "The request failed. Try again." used to stand in for both.
    static func refusalSentence(status: Int, body: Data) -> String {
        let text = String(decoding: body, as: UTF8.self)
        let parsed: Any
        do {
            parsed = try JSONSerialization.jsonObject(with: body)
        } catch {
            return "Spis refused the request with HTTP \(status): \(text)"
        }
        guard let object = parsed as? [String: Any],
            let sentence = object["error"] as? String, !sentence.isEmpty
        else {
            return "Spis refused the request with HTTP \(status): \(text)"
        }
        return sentence
    }

    /// One NDJSON stream line as an event with its type. A line that is not
    /// one fails the operation naming it: skipped, a damaged result line
    /// ended as "closed early" and log lines vanished from the output.
    static func streamEvent(_ line: String) throws -> (type: String, event: [String: Any]) {
        let parsed: Any
        do {
            parsed = try JSONSerialization.jsonObject(with: Data(line.utf8))
        } catch {
            throw SpisClientError.unreadableEvent("\(line) (\(error.localizedDescription))")
        }
        guard let event = parsed as? [String: Any], let type = event["type"] as? String else {
            throw SpisClientError.unreadableEvent(line)
        }
        return (type, event)
    }
}
