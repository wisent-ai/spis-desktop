import AppKit
import SwiftUI
import WisentDesignSystem
import WisentDesktopUpdate

@main
struct ReferenceApp: App {
    @NSApplicationDelegateAdaptor(SpisAppDelegate.self) private var delegate

    /// The app's one updater: it drives the scheduled feed checks and backs the
    /// three items `WisentCheckForUpdatesCommand` puts under the app menu. A
    /// second instance would give the menu its own `SPUUpdater`, so the toggles
    /// would report and change settings that the checking updater never reads.
    @StateObject private var updater = WisentUpdater()

    var body: some Scene {
        WindowGroup("Spis") {
            SpisRootContent(
                model: delegate.model,
                manageModel: delegate.manageModel,
                onboarding: delegate.onboarding
            )
        }
        .windowToolbarStyle(.unified)
        .commands {
            CommandGroup(after: .appInfo) {
                WisentCheckForUpdatesCommand(updater: updater)
            }
        }
    }
}

/// Guarantees that Spis owns a window at launch. SwiftUI declines to open a
/// fresh window when it has persistent state to restore but the saved view tree
/// no longer exists, and every change to the window's root view invalidates that
/// tree — the `.textSelection` rule below is one such change. The app then comes
/// up alive with `window=0x0` and nothing on screen, which from the outside is
/// indistinguishable from a crash on launch. `wisentEnsureWindow` opens the same
/// content in a plain window whenever the scene has produced none, and answers
/// `nil` on a normal launch; the result is retained because releasing it would
/// close the only window the operator has.
///
/// Both models live here rather than in the `App` struct so the scene and the
/// fallback window read one instance each: a second `AppModel` would give the
/// fallback window its own catalogs, corpus root and run log.
@MainActor
final class SpisAppDelegate: NSObject, NSApplicationDelegate {
    let model = AppModel()
    let manageModel = ManageModel()
    let onboarding = SpisOnboardingController()
    private var fallbackWindow: NSWindow?

    func applicationDidFinishLaunching(_ notification: Notification) {
        DispatchQueue.main.async { [self] in
            fallbackWindow = wisentEnsureWindow(
                title: "Spis",
                size: CGSize(width: 1080, height: 680)
            ) {
                SpisRootContent(
                    model: model,
                    manageModel: manageModel,
                    onboarding: onboarding
                )
            }
        }
    }
}

/// The one description of Spis's window contents, rendered by both the
/// `WindowGroup` scene and the delegate's fallback window so the two can never
/// disagree about what the window holds or which surface is on screen.
private struct SpisRootContent: View {
    let model: AppModel
    let manageModel: ManageModel
    let onboarding: SpisOnboardingController

    var body: some View {
        AppRootView()
            .environment(model)
            .environment(manageModel)
            .environment(onboarding)
            .frame(minWidth: 1080, minHeight: 680)
            // Every fact Spis reports is selectable, and therefore
            // copyable. This app exists to state things a person then
            // quotes somewhere else — a corpus path, a page URL, the
            // stdout of a check, a refusal sentence — and SwiftUI's
            // `Text` refuses selection on macOS unless a view asks, which
            // left 46 of 51 text sites in this window dead to Cmd-C while
            // five had been fixed one at a time.
            //
            // `.textSelection` travels through the environment, so one
            // call at the root of the window's content covers all three
            // surfaces the picker switches between — Browse, Docs, Manage —
            // and every screen added after this one. It sits here rather
            // than inside `AppRootView` or on a `NavigationSplitView` column
            // because those are branches: each would answer the question
            // for itself and leave its siblings unselectable. And because
            // this description is what both the scene and the fallback
            // window render, the rule holds in whichever window the operator
            // ends up with, from a single call site.
            .textSelection(.enabled)
            .task { model.load(); manageModel.reloadTypes() }
            .task { await onboarding.start() }
            // The walkthrough's one presentation: an overlay over the whole
            // window, not a second window and not a sheet on one surface. It
            // sits on this description rather than inside `AppRootView` so the
            // scene window and the delegate's fallback window show the same
            // journey from one call site, and so the surface picker underneath
            // stays covered until the journey closes.
            .overlay {
                if onboarding.isPresented {
                    SpisOnboardingView(
                        screen: onboarding.screen,
                        errorMessage: onboarding.errorMessage,
                        isFinalScreen: onboarding.isFinalScreen,
                        continueJourney: { Task { await onboarding.advance() } },
                        onAdopted: {
                            Task {
                                await onboarding.finishAfterAdoption(
                                    catalogAvailable: model.selectedCatalog != nil
                                )
                            }
                        },
                        retry: { Task { await onboarding.retry() } }
                    )
                }
            }
    }
}

struct AppRootView: View {
    @State private var surface = "browse"

    var body: some View {
        VStack(spacing: 0) {
            Picker("Surface", selection: $surface) {
                Text("Browse").tag("browse")
                Text("Docs").tag("docs")
                Text("Crawlers").tag("crawlers")
                Text("Manage").tag("manage")
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .padding(8)

            switch surface {
            case "browse": ContentView()
            case "docs": DocsCorpusView()
            case "crawlers": CrawlersView()
            default: ManageView()
            }
        }
    }
}
