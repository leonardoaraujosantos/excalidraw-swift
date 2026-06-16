import XCTest
@testable import ExcalidrawModel

final class LocalizationTests: XCTestCase {
    func testTranslatesKnownKey() {
        XCTAssertEqual(Localization.string("labels.copy", in: Localization.spanish), "Copiar")
        XCTAssertEqual(Localization.string("labels.copy", in: Localization.arabic), "نسخ")
    }

    func testFallsBackToEnglishThenKey() {
        let partial = Locale(code: "xx", direction: .ltr, strings: ["labels.copy": "Kopio"])
        XCTAssertEqual(Localization.string("labels.copy", in: partial), "Kopio")
        // Missing in the locale → English fallback.
        XCTAssertEqual(Localization.string("labels.delete", in: partial), "Delete")
        // Missing everywhere → the raw key.
        XCTAssertEqual(Localization.string("labels.unknown", in: partial), "labels.unknown")
    }

    func testResolvesLanguageTag() {
        XCTAssertEqual(Localization.locale(for: "es-ES").code, "es")
        XCTAssertEqual(Localization.locale(for: "AR").code, "ar")
        XCTAssertEqual(Localization.locale(for: "fr").code, "en") // unknown → English
    }

    func testArabicIsRightToLeft() {
        XCTAssertTrue(Localization.arabic.isRTL)
        XCTAssertFalse(Localization.english.isRTL)
        XCTAssertEqual(Localization.english.direction, .ltr)
    }

    func testEveryLocaleCoversEnglishKeys() {
        let keys = Set(Localization.english.strings.keys)
        for locale in Localization.all {
            XCTAssertEqual(Set(locale.strings.keys), keys, "\(locale.code) is missing keys")
        }
    }
}
