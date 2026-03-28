import XCTest
@testable import SkillsMaster

final class AppLocalizationTests: XCTestCase {

    func testStringResolvesEnglishWhenLanguageModeIsEnglish() {
        let defaults = UserDefaults(suiteName: #function)!
        defaults.removePersistentDomain(forName: #function)
        defaults.set(AppLanguageMode.english.rawValue, forKey: Constants.appLanguageModeKey)

        XCTAssertEqual(AppLocalization.string("General", userDefaults: defaults), "General")
    }

    func testStringResolvesSimplifiedChineseWhenLanguageModeIsChinese() {
        let defaults = UserDefaults(suiteName: #function)!
        defaults.removePersistentDomain(forName: #function)
        defaults.set(AppLanguageMode.simplifiedChinese.rawValue, forKey: Constants.appLanguageModeKey)

        XCTAssertEqual(AppLocalization.string("General", userDefaults: defaults), "通用")
    }
}
