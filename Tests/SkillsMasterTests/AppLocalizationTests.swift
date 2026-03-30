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

    func testStringResolvesTranslatedRepositoryLabelWhenLanguageModeIsChinese() {
        let defaults = UserDefaults(suiteName: #function)!
        defaults.removePersistentDomain(forName: #function)
        defaults.set(AppLanguageMode.simplifiedChinese.rawValue, forKey: Constants.appLanguageModeKey)

        XCTAssertEqual(AppLocalization.string("Repositories", userDefaults: defaults), "仓库")
    }

    func testDetailLocalizationKeysResolveInChinese() {
        let defaults = UserDefaults(suiteName: #function)!
        defaults.removePersistentDomain(forName: #function)
        defaults.set(AppLanguageMode.simplifiedChinese.rawValue, forKey: Constants.appLanguageModeKey)

        XCTAssertEqual(AppLocalization.string("Update", userDefaults: defaults), "更新")
        XCTAssertEqual(AppLocalization.string("Copy path to clipboard", userDefaults: defaults), "复制路径到剪贴板")
    }

    func testServiceDisplayNamesResolveLocalizedLabelsWhenLanguageModeIsChinese() {
        let standardDefaults = UserDefaults.standard
        let previousValue = standardDefaults.string(forKey: Constants.appLanguageModeKey)
        defer {
            if let previousValue {
                standardDefaults.set(previousValue, forKey: Constants.appLanguageModeKey)
            } else {
                standardDefaults.removeObject(forKey: Constants.appLanguageModeKey)
            }
        }

        standardDefaults.set(AppLanguageMode.simplifiedChinese.rawValue, forKey: Constants.appLanguageModeKey)

        XCTAssertEqual(SkillRegistryService.LeaderboardCategory.allTime.displayName, "总榜")
        XCTAssertEqual(SkillRegistryService.LeaderboardCategory.trending.displayName, "趋势（24 小时）")
        XCTAssertEqual(SkillRegistryService.LeaderboardCategory.hot.displayName, "热门")
        XCTAssertEqual(ClawHubService.SkillSort.newest.displayName, "最新")
        XCTAssertEqual(ClawHubService.SortDirection.descending.displayName, "降序")
        XCTAssertEqual(ClawHubService.SortDirection.ascending.displayName, "升序")
    }
}
