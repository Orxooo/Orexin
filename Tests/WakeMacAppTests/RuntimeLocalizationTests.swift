// SPDX-License-Identifier: GPL-3.0-only
// Copyright (c) 2026 Orxooo
import XCTest
@testable import WakeMac

final class RuntimeLocalizationTests: XCTestCase {
    private func bundle(_ language: AppLanguage) throws -> Bundle {
        let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
            .deletingLastPathComponent().deletingLastPathComponent()
        return try XCTUnwrap(Bundle(path: root.appendingPathComponent("Resources/Localization/\(language.rawValue).lproj").path))
    }

    func testExistingHistoryCanBePresentedInDifferentLanguagesWithoutRewritingIt() throws {
        let stored = "工作会话已延长 15 分钟。"
        XCTAssertEqual(localizedMessage(stored, bundle: try bundle(.english), language: .english), "Work session extended by 15 min.")
        XCTAssertEqual(localizedMessage(stored, bundle: try bundle(.german), language: .german), "Arbeitssitzung um 15 Min. verlängert.")
        XCTAssertEqual(stored, "工作会话已延长 15 分钟。")
    }

    func testNumericHistoryAndMultilineErrorsResolveAcrossAllCatalogs() throws {
        let battery = "电量 14%，低于 15% 时将倒计时休眠。"
        let error = "切换失败：临时锁屏会话已失效。\n系统尚未恢复即时密码保护。"
        for language in AppLanguage.allCases where language != .simplifiedChinese {
            let resources = try bundle(language)
            let translated = localizedMessage(battery, bundle: resources, language: language)
            XCTAssertNotEqual(translated, battery, language.rawValue)
            XCTAssertTrue(translated.contains("14%"), language.rawValue)
            XCTAssertTrue(translated.contains("15%"), language.rawValue)
            let failure = localizedMessage(error, bundle: resources, language: language)
            XCTAssertNotEqual(failure, error, language.rawValue)
            XCTAssertFalse(failure.contains("临时锁屏"), language.rawValue)
            XCTAssertFalse(failure.contains("系统尚未"), language.rawValue)
            XCTAssertEqual(failure.components(separatedBy: "\n").count, 2, language.rawValue)
        }
    }

    func testUnknownUserContentIsPreserved() throws {
        let commandOutput = "自定义任务完成 / Users / 2049"
        XCTAssertEqual(localizedMessage(commandOutput, bundle: try bundle(.english), language: .english), commandOutput)
    }
}
