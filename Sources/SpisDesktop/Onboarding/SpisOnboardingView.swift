import Foundation
import SwiftUI
import WisentDesignSystem
import WisentOnboarding

// The first-run walkthrough on screen, and the Manage row that shows it
// again.
//
// Split out of `SpisOnboarding.swift`, which had grown past the
// three-hundred-line limit; the controller stays there.

/// The words come from the journey definition and the app's wisent-texts
/// catalogue rather than from this file: a screen reads by its `title_key`
/// and `body_key` in the system's language (`SpisWords`), its English being
/// the definition's `presentation.title` and `presentation.body`, and the
/// panel's own lines are catalogue keys too. The step counter is the
/// definition's — three screens, and the position of the current one.
struct SpisOnboardingView: View {
    let screen: JourneyScreen?
    let errorMessage: String?
    let isFinalScreen: Bool
    let continueJourney: () -> Void
    let onAdopted: () -> Void
    let retry: () -> Void

    var body: some View {
        ZStack {
            WisentCanvasBackground()
            WisentDesign.canvas.opacity(0.92)
                .ignoresSafeArea()

            WisentPanel(padding: WisentDesign.Space.x6) {
                VStack(alignment: .leading, spacing: WisentDesign.Space.x6) {
                    header
                    copy

                    if isFinalScreen {
                        SpisCorpusAdoptionView(compact: true, onAdopted: onAdopted)
                    }

                    if let errorMessage {
                        Label(errorMessage, systemImage: "exclamationmark.triangle.fill")
                            .font(WisentTypography.bodyMedium(13))
                            .foregroundStyle(WisentDesign.danger)
                            .fixedSize(horizontal: false, vertical: true)
                    }

                    if !isFinalScreen || screen == nil {
                        HStack {
                            Spacer()
                            if screen == nil {
                                Button(SpisWords.say("walkthrough.try_again", english: "Try Again"), action: retry)
                                    .buttonStyle(WisentPrimaryButtonStyle())
                                    .keyboardShortcut(.defaultAction)
                            } else {
                                Button(SpisWords.say("walkthrough.continue", english: "Continue"), action: continueJourney)
                                    .buttonStyle(WisentPrimaryButtonStyle())
                                    .keyboardShortcut(.defaultAction)
                            }
                        }
                    }
                }
            }
            .frame(width: 700)
            .padding(WisentDesign.Space.x8)
        }
        .accessibilityLabel(SpisWords.say("walkthrough.accessibility", english: "Spis first-run walkthrough"))
    }

    private var header: some View {
        HStack(spacing: WisentDesign.Space.x3) {
            VStack(alignment: .leading, spacing: WisentDesign.Space.x1) {
                Text(SpisWords.say("walkthrough.eyebrow", english: "SPIS REFERENCE CORPUS"))
                    .font(WisentTypography.monoSemibold(10))
                    .tracking(0.7)
                    .foregroundStyle(WisentDesign.brand)
                Text(SpisWords.say("walkthrough.tagline", english: "The measured state of the corpus, in one window"))
                    .font(WisentTypography.body(13))
                    .foregroundStyle(WisentDesign.secondary)
            }

            Spacer()

            if let step = stepLabel {
                WisentBadge(step, symbol: symbol, tone: .brand)
            }
        }
    }

    private var copy: some View {
        VStack(alignment: .leading, spacing: WisentDesign.Space.x2) {
            Text(titleText)
                .font(WisentTypography.display(30))
                .foregroundStyle(WisentDesign.ink)
                .fixedSize(horizontal: false, vertical: true)
            Text(bodyText)
                .font(WisentTypography.body(16))
                .foregroundStyle(WisentDesign.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var titleText: String {
        if let text = SpisWords.screen(screen?.titleKey, english: presentationString("title")) { return text }
        return screen == nil
            ? SpisWords.say("walkthrough.unavailable.title", english: "First-run walkthrough unavailable")
            : SpisWords.say("walkthrough.fallback.title", english: "Continue setting up Spis")
    }

    private var bodyText: String {
        if let text = SpisWords.screen(screen?.bodyKey, english: presentationString("body")) { return text }
        return screen == nil
            ? SpisWords.say("walkthrough.unavailable.body", english: "The bundled walkthrough could not be read. Nothing in the corpus has been changed.")
            : SpisWords.say("walkthrough.fallback.body", english: "Follow this step to reach the first catalog Spis can report on.")
    }

    private var stepLabel: String? {
        guard let screen, let index = Self.order.firstIndex(of: screen.screenId) else { return nil }
        return SpisWords.say(
            "walkthrough.step",
            ["current": "\(index + 1)", "total": "\(Self.order.count)"],
            english: "Step {current} of {total}"
        )
    }

    private var symbol: String {
        switch screen?.screenKind {
        case "promise": "square.grid.2x2"
        case "explanation": "arrow.triangle.branch"
        case "first_success": "checklist.checked"
        default: "square.grid.2x2"
        }
    }

    private func presentationString(_ key: String) -> String? {
        guard case .string(let value)? = screen?.presentation[key],
            !value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        else { return nil }
        return value
    }

    private static let order = ["promise", "read_and_write", "adopt_corpus"]
}

/// The control that shows the walkthrough again.
///
/// Spis has no Settings scene and no preferences window — the app is four
/// surfaces behind one picker — so this row lives last on Manage, the only
/// surface whose controls write instead of report, under the records it does
/// not change. It is reachable there whether or not a product type is
/// selected, which the Manage detail pane otherwise is not.
struct SpisFirstRunWalkthroughRow: View {
    @Environment(SpisOnboardingController.self) private var onboarding
    @State private var outcome: WisentMutationOutcome = .idle

    var body: some View {
        WisentSectionBox(
            title: SpisWords.say("walkthrough.row.title", english: "First-run walkthrough"),
            detail: SpisWords.say("walkthrough.row.detail", english: "See the walkthrough this product shows on a first run.")
        ) {
            WisentPanel {
                VStack(alignment: .leading, spacing: WisentDesign.Space.x3) {
                    Button(SpisWords.say("walkthrough.row.show_again", english: "Show it again")) { showAgain() }
                        .buttonStyle(WisentSecondaryButtonStyle())
                        .disabled(isReplaying)
                    if outcome != .idle {
                        WisentMutationBar(outcome: outcome) { outcome = .idle }
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }

    private var isReplaying: Bool { onboarding.isWorking || outcome.isWorking }

    /// The local `.working` line is what closes the control, not
    /// `onboarding.isWorking`: the journey does not raise that flag until the
    /// task below is scheduled, and a second press lands in the gap.
    private func showAgain() {
        guard !isReplaying else { return }
        outcome = .working(SpisWords.say("walkthrough.row.starting", english: "Starting the walkthrough…"))
        Task { outcome = await onboarding.replay() }
    }
}
