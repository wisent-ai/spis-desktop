import Foundation
import WisentOnboarding

// The transport the controller reads its journey through: it accepts a
// published definition only when the version and the first-success fact are
// the ones this build knows.
//
// Split out of `SpisOnboarding.swift`, which had grown past the
// three-hundred-line limit.

/// A control plane serving a newer version to an older app would walk the
/// operator through screens whose facts this build never reports, so a
/// mismatch falls back to the bundled definition rather than being rendered.
struct SpisJourneyTransport: JourneyTransport {
    let upstream: EnvironmentJourneyTransport
    let requiredJourneyVersion: String
    let requiredFirstSuccessFact: String

    func readBundle(productId: String, journeyId: String) async throws -> JourneyBundle {
        let bundle = try await upstream.readBundle(productId: productId, journeyId: journeyId)
        guard bundle.definition.journeyVersion == requiredJourneyVersion,
              bundle.definition.firstSuccessFact == requiredFirstSuccessFact
        else {
            throw JourneyClientError.invalid("central journey identity")
        }
        return bundle
    }

    func readState(productId: String, attemptId: UUID, subjectHash: String) async throws -> JSONValue? {
        try await upstream.readState(
            productId: productId,
            attemptId: attemptId,
            subjectHash: subjectHash
        )
    }

    func assignExperiment(request: JourneyAssignmentRequest) async throws -> JourneyAssignmentResponse {
        try await upstream.assignExperiment(request: request)
    }

    func collect(event: JourneyRuntimeEvent) async throws {
        try await upstream.collect(event: event)
    }
}

// MARK: - Presentation

/// The walkthrough, over the window.
///
