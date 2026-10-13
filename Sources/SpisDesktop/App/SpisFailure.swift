import Foundation
import WisentErrors

/// How every screen reports an operation that threw: the code is read from
/// the error's own type, and a backend that could not be started is reported
/// at the backend's start point rather than at the screen that asked for it.
enum SpisFailure {
    /// A missing or incomplete install is our deployment (`config`); a backend
    /// that ran and would not start, an unreadable response or a dropped
    /// connection is the service being down (`infra_down`); the backend's own
    /// refusal is `refused`; a corpus location that cannot be used is
    /// `config`. Only an error none of these types describes is `unknown`.
    static func code(of error: Error) -> WisentErrors.Code {
        switch error {
        case let backend as SpisBackendError:
            return backend.isMissingInstall ? .config : .infraDown
        case SpisClientError.refusal:
            return .refused
        case is SpisClientError, is URLError:
            return .infraDown
        case is CorpusLocationError:
            return .config
        default:
            return .unknown
        }
    }

    static func report(_ error: Error, at point: String) {
        WisentFailureReporter.shared.report(
            failurePoint: error is SpisBackendError ? "spis.backend-start" : point,
            code: code(of: error).rawValue,
            service: "spis",
            detail: error.localizedDescription
        )
    }

    /// An operation that ran and ended refused: the product's own refusal
    /// sentence, reported where it became the outcome panel's state.
    static func reportRefusal(_ refusal: String, at point: String) {
        WisentFailureReporter.shared.report(
            failurePoint: point,
            code: WisentErrors.Code.refused.rawValue,
            service: "spis",
            detail: refusal
        )
    }
}
