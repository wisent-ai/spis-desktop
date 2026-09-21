import Foundation
import SwiftUI
import WisentDesignSystem
import WisentOnboarding

/// Spis's first-run walkthrough, and the control that shows it again.
///
/// The journey itself is Echo's: `JourneyClient` decides which screen is
/// current, records the attempt, and reports the funnel. This controller owns
/// only what Spis knows — whether a real catalog is on screen, which is the
/// fact the last screen waits for — and the presentation state the window's
/// overlay reads.
@MainActor
@Observable
final class SpisOnboardingController {
    private enum Constants {
        static let productID = "spis-desktop"
        static let journeyID = "first-use"
        static let journeyVersion = "2026-09-05.1"
        static let firstSuccessFact = "corpus_adopted"
        static let evidenceRevision = "spis-desktop-onboarding-2026-09-05.1"
        static let fallbackVersionID = UUID(uuidString: "5BD5E39A-4D63-4777-9A91-F6EABF9BE9EF")!
        static let storageNamespace = "ai.wisent.spis.onboarding.2026-09-05.1"
        static let deviceIDKey = "ai.wisent.spis.onboarding.device-id"
        static let resourceName = "spis-desktop-first-use"
    }

    private enum State: Equatable {
        case loading
        case presenting
        case completed
    }

    private(set) var screen: JourneyScreen?
    private(set) var errorMessage: String?
    private var state: State = .loading

    private var client: JourneyClient?
    private var hasStarted = false
    private var exposedScreenID: String?

    /// The window shows the walkthrough exactly while this is true. A journey
    /// that failed to load still presents, so the operator gets a screen with
    /// a reason and a retry rather than a window that silently swallowed it.
    var isPresented: Bool { state == .presenting }

    var isFinalScreen: Bool { screen?.transitions.isEmpty == true }

    var isWorking = false

    func start() async {
        guard !hasStarted else { return }
        hasStarted = true
        state = .loading
        errorMessage = nil

        do {
            let (client, progress) = try await bootstrap()
            self.client = client
            screen = await client.currentScreen

            if progress.status == .completed {
                state = .completed
                try? await client.flush()
            } else {
                state = .presenting
                try await expose(using: client)
            }
        } catch {
            screen = nil
            errorMessage = "Spis couldn’t load its first-run walkthrough. Try again to continue."
            state = .presenting
        }
    }

    func advance() async {
        guard let client, !isFinalScreen else { return }
        errorMessage = nil
        do {
            guard try await client.advance(
                evidence: [:],
                evidenceRevision: Constants.evidenceRevision
            ) != nil else { return }
            screen = await client.currentScreen
            try await expose(using: client)
        } catch {
            errorMessage = "Spis couldn’t save this step. Try again."
        }
    }

    /// Closes the walkthrough only after the product-owned adoption operation
    /// has persisted a corpus location and the application can decode a catalog
    /// from that accepted root.
    func finishAfterAdoption(catalogAvailable: Bool) async {
        guard let client, isFinalScreen else { return }
        errorMessage = nil
        guard catalogAvailable else {
            errorMessage = "The corpus location was saved, but no catalog could be decoded from it. Choose the corpus again to see the exact refusal."
            return
        }
        let evidence: [String: JSONValue] = [Constants.firstSuccessFact: .boolean(true)]
        do {
            try await client.observeFirstSuccess(
                evidence: evidence,
                evidenceRevision: Constants.evidenceRevision
            )
            let completed = try await client.complete(
                evidence: evidence,
                evidenceRevision: Constants.evidenceRevision
            )
            guard completed else {
                errorMessage = "Spis couldn’t record the accepted corpus. You can continue using it and replay first use from Manage."
                return
            }
            state = .completed
            screen = nil
            exposedScreenID = nil
            try? await client.flush()
        } catch {
            errorMessage = "Spis couldn’t record the accepted corpus. You can continue using it and replay first use from Manage."
        }
    }

    func retry() async {
        client = nil
        screen = nil
        exposedScreenID = nil
        hasStarted = false
        await start()
    }

    /// Settings asking for the walkthrough a second time.
    ///
    /// Completing it once made it unreachable, so an operator who clicked
    /// through it could never read it again. The attempt is reset through the
    /// same client that recorded it — Echo sees one `onboarding_reset` against
    /// this subject rather than a second parallel attempt — and the walkthrough
    /// returns over the window already on screen, in this session, because that
    /// is what was asked for and not a note to look again after the next
    /// launch. The outcome is returned rather than absorbed, so the row that
    /// was clicked states what happened.
    ///
    /// A journey that never loaded its progress — the root task failed, or the
    /// operator reached this control first — is started here rather than
    /// refused: a dead control is worse than a slow one.
    func replay() async -> WisentMutationOutcome {
        guard !isWorking else { return .idle }
        isWorking = true
        defer { isWorking = false }
        do {
            let client: JourneyClient
            if let started = self.client {
                client = started
            } else {
                (client, _) = try await bootstrap()
                self.client = client
                hasStarted = true
            }
            try await client.reset(evidenceRevision: Constants.evidenceRevision)
            screen = await client.currentScreen
            errorMessage = nil
            exposedScreenID = nil
            state = .presenting
            try await expose(using: client)
            try await client.flush()
            return .succeeded("Started. The walkthrough is over this window.")
        } catch {
            return .failed(Self.replayFailure(error))
        }
    }

    /// Why a replay failed, in a sentence an operator can act on.
    ///
    /// `JourneyClientError` carries no localization, so `localizedDescription`
    /// renders it as "error 3" and names nothing.
    private static func replayFailure(_ error: Error) -> String {
        guard let journeyError = error as? JourneyClientError else {
            return (error as? LocalizedError)?.errorDescription ?? String(describing: error)
        }
        switch journeyError {
        case .notStarted:
            return "The walkthrough did not load in this session, so there is nothing to show."
        case .storage:
            return "The walkthrough's progress could not be written on this machine."
        case .transport:
            return "The onboarding service could not be reached."
        case let .invalid(reason):
            return reason
        }
    }

    /// One `onboarding_step_viewed` per screen actually shown. Re-exposing the
    /// same screen would count a view the operator never had.
    private func expose(using client: JourneyClient) async throws {
        guard let screen, screen.screenId != exposedScreenID else { return }
        try await client.expose(evidenceRevision: Constants.evidenceRevision)
        exposedScreenID = screen.screenId
    }

    private func bootstrap() async throws -> (JourneyClient, JourneyProgress) {
        let fallback = try Self.loadFallback()
        let subjectHash = JourneySubject.scoped([
            Constants.productID,
            JourneyScope.device.rawValue,
            Self.deviceID()
        ])
        let transport = SpisJourneyTransport(
            upstream: EnvironmentJourneyTransport(
                tokenEnvironmentKey: "SPIS_DESKTOP_STADO_INTEGRATION_TOKEN"
            ),
            requiredJourneyVersion: Constants.journeyVersion,
            requiredFirstSuccessFact: Constants.firstSuccessFact
        )
        let client = try JourneyClient(
            productId: Constants.productID,
            journeyId: Constants.journeyID,
            subjectHash: subjectHash,
            scope: .device,
            transport: transport,
            storage: UserDefaultsJourneyStorage(namespace: Constants.storageNamespace),
            fallback: fallback
        )
        let (_, progress) = try await client.start(evidenceRevision: Constants.evidenceRevision)
        return (client, progress)
    }

    /// The bundled definition, which is also the identity check: a resource
    /// that no longer names this version or this first-success fact is a
    /// mismatch between the app and its journey, not a journey to present.
    private static func loadFallback() throws -> JourneyBundle {
        // One loader for the whole fleet: JourneyResource resolves the
        // packaged bundle and throws a named error saying which paths it
        // tried, instead of SwiftPM's accessor trapping on a machine that
        // never built this binary.
        let canonicalDefinition = try String(
            decoding: JourneyResource.definitionData(
                resource: Constants.resourceName,
                bundleName: "SpisDesktop_SpisDesktop.bundle"
            ),
            as: UTF8.self
        )
        let bundle = try JourneyRouter.makeBundle(
            canonicalDefinition: canonicalDefinition,
            journeyVersionId: Constants.fallbackVersionID
        )
        guard bundle.definition.journeyVersion == Constants.journeyVersion,
              bundle.definition.firstSuccessFact == Constants.firstSuccessFact
        else {
            throw JourneyClientError.invalid("bundled fallback identity")
        }
        return bundle
    }

    /// This machine, named once and kept. The journey is scoped to the device
    /// because Spis has no account: the corpus it reads is on this disk.
    private static func deviceID() -> String {
        let defaults = UserDefaults.standard
        if let stored = defaults.string(forKey: Constants.deviceIDKey),
           !stored.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return stored
        }
        let created = UUID().uuidString.lowercased()
        defaults.set(created, forKey: Constants.deviceIDKey)
        return created
    }
}

/// The central journey, accepted only when it is the journey this build knows.
///
