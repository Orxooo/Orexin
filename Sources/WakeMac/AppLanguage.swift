// SPDX-License-Identifier: GPL-3.0-only
// Copyright (c) 2026 Orxooo
import Foundation

enum AppLanguage: String, CaseIterable, Identifiable {
    case simplifiedChinese = "zh-Hans"
    case traditionalChinese = "zh-Hant"
    case english = "en"
    case japanese = "ja"
    case french = "fr"
    case german = "de"
    case spanish = "es"

    var id: String { rawValue }
    var name: String {
        switch self {
        case .simplifiedChinese: "简体中文"
        case .traditionalChinese: "繁體中文"
        case .english: "English"
        case .japanese: "日本語"
        case .french: "Français"
        case .german: "Deutsch"
        case .spanish: "Español"
        }
    }
    var locale: Locale { Locale(identifier: rawValue) }

    static var selected: AppLanguage {
        AppLanguage(rawValue: UserDefaults.standard.string(forKey: "orexin.appearance.language") ?? "") ?? .simplifiedChinese
    }
}

/// Localize strings assembled at runtime, which SwiftUI cannot resolve as string literals.
func L(_ key: String) -> String {
    let language = AppLanguage.selected
    guard let bundle = languageBundles[language.rawValue] else { return key }
    return localizedMessage(key, bundle: bundle, language: language)
}

func localizedMessage(_ key: String, bundle: Bundle, language: AppLanguage) -> String {
    let translated = bundle.localizedString(forKey: key, value: key, table: nil)
    if translated != key || language == .simplifiedChinese { return translated }
    guard key.unicodeScalars.contains(where: { (0x3400...0x9fff).contains($0.value) }) else { return key }
    // History stays in its original form on disk. Localize known event prefixes
    // when presenting it, including records written before a language change.
    for prefix in eventPrefixes where key.hasPrefix(prefix) {
        return bundle.localizedString(forKey: prefix, value: prefix, table: nil)
            + localizedMessage(String(key.dropFirst(prefix.count)), bundle: bundle, language: language)
    }
    for format in historyFormats {
        let range = NSRange(key.startIndex..<key.endIndex, in: key)
        guard let match = format.expression.firstMatch(in: key, range: range) else { continue }
        let values: [CVarArg] = (1..<match.numberOfRanges).compactMap { index in
            Range(match.range(at: index), in: key).map { String(key[$0]) as CVarArg }
        }
        let template = bundle.localizedString(forKey: format.key, value: format.key, table: nil)
        return String(format: template, locale: language.locale, arguments: values)
    }
    if key.contains("\n") {
        return key.components(separatedBy: "\n").map { localizedMessage($0, bundle: bundle, language: language) }.joined(separator: "\n")
    }
    return key
}

func LF(_ key: String, _ arguments: CVarArg...) -> String {
    String(format: L(key), locale: AppLanguage.selected.locale, arguments: arguments)
}

private let languageBundles: [String: Bundle] = Dictionary(uniqueKeysWithValues: AppLanguage.allCases.compactMap { language in
    guard let path = Bundle.main.path(forResource: language.rawValue, ofType: "lproj"), let bundle = Bundle(path: path) else { return nil }
    return (language.rawValue, bundle)
})

private let eventPrefixes = [
    "模式已核验：", "切换模式：", "自动切换：", "自动触发：", "会话已开始：", "会话已结束：", "会话结束：", "会话启动失败：", "定时休眠：",
    "切换失败：", "状态读取失败：", "温度保护释放失败：", "登录启动设置失败：", "命令启动或日志处理失败：", "操作超时：",
    "清空失败，现有记录已保留：", "导出失败：", "屏幕策略未核验：", "屏幕亮度恢复失败：",
    "工作会话已失效，已释放本应用的保活。\n", "工作会话已失效；恢复未完成：\n", "系统回读与所选模式不一致，未标记为成功。\n",
    "\n恢复休眠也失败：",
]

private struct HistoryFormat {
    let expression: NSRegularExpression
    let key: String
}
private let historyFormats: [HistoryFormat] = [
    (#"^低电量保护：([0-9]+)%$"#, "低电量保护：%@%%"),
    (#"^电量 ([0-9]+)%，低于 ([0-9]+)% 时将倒计时休眠。$"#, "电量 %@%%，低于 %@%% 时将倒计时休眠。"),
    (#"^工作会话已延长 ([0-9.,]+) 分钟。$"#, "工作会话已延长 %@ 分钟。"),
].compactMap { pattern, key in
    (try? NSRegularExpression(pattern: pattern)).map { HistoryFormat(expression: $0, key: key) }
}
