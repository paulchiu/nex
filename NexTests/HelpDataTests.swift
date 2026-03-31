@testable import Nex
import XCTest

@MainActor
final class HelpDataTests: XCTestCase {
    func testShortcutCategoriesArePopulated() {
        XCTAssertFalse(HelpData.shortcutCategories.isEmpty)
        for category in HelpData.shortcutCategories {
            XCTAssertFalse(category.shortcuts.isEmpty, "\(category.name) has no shortcuts")
        }
    }

    func testGitHubURLIsValid() {
        XCTAssertNotNil(HelpData.githubURL.host)
    }
}
