import SwiftUI
import WisentDesignSystem

/// The GitHub star request Spis makes once, after a person's fifth record
/// added or corpus query answered. Spis counts and words it; `spis serve`
/// hands it over as a `star_request` stream event before a job's result, or
/// as `star_request` beside a docs answer. The window shows it above every
/// surface, whichever one made it, and dismisses it with `star-dismiss`, the
/// same journey `spis star` reads in a terminal.
struct SpisStarRequest: Equatable, Sendable {
    let title: String
    let body: String
    let repository: URL
    let actions: Int

    /// The request a `star_request` object carries; nil for one without a
    /// title, a body, an https repository and a whole count, which the caller
    /// reports as unreadable.
    init?(_ object: [String: Any]) {
        guard let title = object["title"] as? String, !title.isEmpty,
            let body = object["body"] as? String,
            let link = object["repository"] as? String,
            let repository = URL(string: link), repository.scheme == "https",
            let actions = object["actions"] as? Int
        else { return nil }
        self.title = title
        self.body = body
        self.repository = repository
        self.actions = actions
    }
}

/// The one request on screen, shared by every surface that runs a job.
@MainActor
@Observable
final class SpisStarRequestStore {
    static let shared = SpisStarRequestStore()

    var request: SpisStarRequest?
    var failure: String?
    private let backend = SpisBackendProcess()

    func show(_ request: SpisStarRequest) {
        self.request = request
        failure = nil
    }

    /// The request was seen; Spis already recorded it as shown.
    func close() {
        request = nil
        failure = nil
    }

    /// Never ask again: `star-dismiss`, closed once Spis answers with the
    /// `dismissed` stage. A refusal stays on screen with Spis's sentence.
    func dismiss() async {
        failure = nil
        do {
            let base = try await backend.endpoint()
            let data = try await SpisClient(baseURL: base).starDismiss()
            guard let answer = try JSONSerialization.jsonObject(with: data) as? [String: Any],
                answer["stage"] as? String == "dismissed"
            else {
                failure =
                    "Spis answered star-dismiss without a dismissed stage: \(String(decoding: data, as: UTF8.self))"
                return
            }
            request = nil
        } catch {
            failure = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
        }
    }
}

/// The request as the window shows it: Star on GitHub opens the repository
/// Spis named, Not now hides it, Don't ask again dismisses it in Spis.
struct SpisStarRequestPanel: View {
    let store: SpisStarRequestStore
    @Environment(\.openURL) private var openURL

    var body: some View {
        if let request = store.request {
            WisentAlertPanel(
                tone: .info,
                title: request.title,
                detail: [request.body, store.failure].compactMap { $0 }.joined(separator: "\n\n"),
                actions: [
                    WisentAction("Star on GitHub", symbol: "star", kind: .primary) {
                        openURL(request.repository)
                        store.close()
                    },
                    WisentAction("Not now", symbol: "clock") { store.close() },
                    WisentAction("Don't ask again", symbol: "xmark") {
                        Task { await store.dismiss() }
                    },
                ]
            )
            .padding(.horizontal, 8)
        }
    }
}
