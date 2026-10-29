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

    func testPersistedEnglishAuthorizationFailureIsLocalizedIncludingChinese() throws {
        let stored = "Request was not activated: Authorize unlocked work from the Orexin interface first"
        for language in AppLanguage.allCases {
            let output = localizedMessage(stored, bundle: try bundle(language), language: language)
            XCTAssertNotEqual(output, stored, language.rawValue)
            XCTAssertFalse(output.contains("Request was not activated"), language.rawValue)
            if language == .simplifiedChinese {
                XCTAssertEqual(output, "工作请求未启动：请在 Orexin 界面完成本次保持未锁定授权。")
            }
        }
    }

    func testRetainedEnglishServiceLifecycleErrorsRenderInChinese() throws {
        let resources = try bundle(.simplifiedChinese)
        let samples = [
            ("Task service is starting", "后台服务正在启动。"),
            ("Task service is stopping", "后台服务正在停止。"),
            ("Orexin is unavailable at /tmp/example/control.sock. Start the background service with orexin service-start. (No such file or directory)", "后台服务连接不可用，请重新检查。"),
        ]
        for (stored, expected) in samples {
            XCTAssertEqual(localizedMessage(stored, bundle: resources, language: .simplifiedChinese), expected)
            for language in AppLanguage.allCases where language != .english {
                let output = localizedMessage(stored, bundle: try bundle(language), language: language)
                XCTAssertFalse(output.contains("Task service is"), language.rawValue)
                XCTAssertFalse(output.contains("Start the background service"), language.rawValue)
            }
        }
    }

    func testCriticalClientAlertsAndDynamicBodiesResolveAcrossShippedLanguages() throws {
        let messages = [
            "Orexin 有新版本", "后台提醒尚未完整启用", "工作状态无法确认", "温度压力已回落",
            "工作保活请求已到期", "工作会话即将结束", "消息提醒", "发送测试提醒",
            "任务 Alpha：期限或心跳租约已到期，已撤销此请求的保活需求，正在核验电源状态；其他工作请求可能仍在运行。",
            "温度保护触发：系统温度压力达到严重，正在释放保活并取消自动休眠；正在执行的命令继续运行。",
            "保活或权限服务的状态读取失败，请检查当前工作模式。\n系统尚未恢复即时密码保护。",
        ]
        for language in AppLanguage.allCases where language != .simplifiedChinese {
            let resources = try bundle(language)
            for message in messages {
                let output = localizedMessage(message, bundle: resources, language: language)
                if language != .traditionalChinese || message != "Orexin 有新版本" {
                    XCTAssertNotEqual(output, message, "\(language.rawValue): \(message)")
                }
                if language != .traditionalChinese {
                    XCTAssertFalse(output.contains("期限或心跳租约"), language.rawValue)
                    XCTAssertFalse(output.contains("正在释放保活"), language.rawValue)
                    XCTAssertFalse(output.contains("请检查当前"), language.rawValue)
                }
            }
        }
    }
}
