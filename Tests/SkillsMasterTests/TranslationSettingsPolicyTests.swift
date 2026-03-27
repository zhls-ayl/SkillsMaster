import XCTest
@testable import SkillsMaster

final class TranslationSettingsPolicyTests: XCTestCase {

    func testIsEnabled_returnsFalseWhenMasterSwitchIsOff() {
        let result = TranslationSettingsPolicy.isEnabled(
            autoTranslationEnabled: false,
            scope: .installed,
            enabledScopes: [.installed, .skillsSh]
        )

        XCTAssertFalse(result)
    }

    func testIsEnabled_returnsFalseWhenScopeIsNil() {
        let result = TranslationSettingsPolicy.isEnabled(
            autoTranslationEnabled: true,
            scope: nil,
            enabledScopes: [.installed]
        )

        XCTAssertFalse(result)
    }

    func testIsEnabled_returnsTrueOnlyForEnabledScope() {
        let enabledScopes: Set<SkillTranslationScope> = [.skillsSh, .repositories]

        XCTAssertTrue(
            TranslationSettingsPolicy.isEnabled(
                autoTranslationEnabled: true,
                scope: .skillsSh,
                enabledScopes: enabledScopes
            )
        )
        XCTAssertFalse(
            TranslationSettingsPolicy.isEnabled(
                autoTranslationEnabled: true,
                scope: .clawHub,
                enabledScopes: enabledScopes
            )
        )
    }
}
