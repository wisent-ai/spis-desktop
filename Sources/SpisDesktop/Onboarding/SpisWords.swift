import Foundation
import WisentOnboarding
import WisentTexts

/// The walkthrough's words in the language the person reads: the shared
/// wisent-texts catalogue of this app (`Resources/texts`, every Wisent fleet
/// language), its `bundle.json` read once from the packaged resource bundle
/// the way `JourneyResource` reads the journey. The language is the system's
/// first preferred one; a language the fleet lacks reads English.
enum SpisWords {
    /// The bundle, or why it could not be read: a missing or malformed
    /// bundle names itself instead of trapping, and the screens then read the
    /// journey's English.
    static let loaded: Result<Texts, Error> = Result {
        try read(from: JourneyResource.bundle(named: "SpisDesktop_SpisDesktop.bundle"))
    }

    /// The words a resource bundle carries: its `bundle.json` (SwiftPM's
    /// `.process` flattens `Resources/texts/bundle.json` to the bundle's root).
    static func read(from bundle: Bundle) throws -> Texts {
        guard let url = bundle.url(forResource: "bundle", withExtension: "json")
        else {
            throw JourneyResourceError.resourceNotFound(resource: "bundle.json", bundle: bundle.bundlePath)
        }
        return try Texts(bundle: Data(contentsOf: url))
    }

    static var language: String {
        Locale.preferredLanguages.first ?? Locale.current.identifier
    }

    /// One line of the app in the reader's language; the key's English when
    /// the bundle could not be read.
    static func say(_ key: String, _ values: [String: String] = [:], english: String) -> String {
        guard case .success(let texts) = loaded else { return fill(english, values) }
        let text = texts.say(key, in: language, values)
        return text == key ? fill(english, values) : text
    }

    /// A journey screen's text by its key, the presentation's English when the
    /// language or the bundle lacks it.
    static func screen(_ key: String?, english: String?) -> String? {
        guard let key, case .success(let texts) = loaded else { return english }
        let text = texts.say(key, in: language)
        return text == key ? english : text
    }

    private static func fill(_ text: String, _ values: [String: String]) -> String {
        values.reduce(text) { $0.replacingOccurrences(of: "{\($1.key)}", with: $1.value) }
    }
}
