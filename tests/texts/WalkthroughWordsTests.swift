import Foundation
import WisentTexts
import XCTest

@testable import SpisDesktop

/// The walkthrough reads in every fleet language: the resource bundle
/// `swift build` packages for the app, read with the app's own reader
/// (`SpisWords.read`), holds every key of the catalogue in each of the 65
/// languages besides English, each journey screen's `title_key` and
/// `body_key` are among them, Polish reads Polish and a language the fleet
/// lacks reads English.
final class WalkthroughWordsTests: XCTestCase {
    /// The app's resource bundle beside this test bundle in `.build/<config>`.
    private func resources() throws -> Bundle {
        let name = "SpisDesktop_SpisDesktop.bundle"
        let directory = Bundle(for: Self.self).bundleURL.deletingLastPathComponent()
        guard let bundle = Bundle(url: directory.appendingPathComponent(name)) else {
            XCTFail("no \(name) in \(directory.path); swift build packages the app's words there")
            throw CocoaError(.fileNoSuchFile)
        }
        return bundle
    }

    private func json(_ name: String) throws -> [String: Any] {
        let url = try XCTUnwrap(resources().url(forResource: name, withExtension: "json"), "\(name).json is not packaged")
        return try XCTUnwrap(JSONSerialization.jsonObject(with: Data(contentsOf: url)) as? [String: Any])
    }

    func testEveryFleetLanguageHoldsEveryKey() throws {
        let texts = try SpisWords.read(from: resources())
        let shipped = try json("bundle")
        let keys = try XCTUnwrap(shipped["texts"] as? [String: String]).keys
        let translations = try XCTUnwrap(shipped["translations"] as? [String: [String: String]])
        XCTAssertEqual(translations.count, 65, "the bundle holds every fleet language besides English")
        for (code, words) in translations {
            for key in keys {
                let text = texts.say(key, in: code)
                XCTAssertFalse(text.isEmpty || text == key, "\(code) lacks \(key)")
                XCTAssertEqual(text, words[key])
            }
        }
    }

    func testJourneyScreensAreInTheCatalogue() throws {
        let keys = try XCTUnwrap(json("bundle")["texts"] as? [String: String]).keys
        let screens = try XCTUnwrap(json("spis-desktop-first-use")["screens"] as? [[String: Any]])
        XCTAssertFalse(screens.isEmpty)
        for screen in screens {
            for field in ["title_key", "body_key"] {
                let key = try XCTUnwrap(screen[field] as? String)
                XCTAssertTrue(keys.contains(key), "\(key) of the journey is not in texts/catalogue.json")
            }
        }
    }

    func testPolishReadsPolishAndAnUnknownLanguageReadsEnglish() throws {
        let texts = try SpisWords.read(from: resources())
        XCTAssertEqual(texts.say("walkthrough.continue", in: "pl-PL"), "Dalej")
        XCTAssertEqual(texts.say("walkthrough.step", in: "pl", ["current": "2", "total": "3"]), "Krok 2 z 3")
        XCTAssertEqual(texts.say("spis.first_use.adopt_corpus.title", in: "pl"), "Wybierz swój istniejący korpus")
        XCTAssertEqual(texts.say("walkthrough.continue", in: "xx"), "Continue")
    }
}
