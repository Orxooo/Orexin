// SPDX-License-Identifier: GPL-3.0-only
// Copyright (c) 2026 Orxooo
import SwiftUI
import AppKit

struct AdvancedView: View {
    @ObservedObject var appearance: AppearanceController
    @ObservedObject var notifier: LocalNotifier
    let availableWidth: CGFloat
    @AppStorage("orexin.appearance.language") private var languageID = "zh-Hans"

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            if availableWidth > 850 {
                HStack(alignment: .top, spacing: 16) {
                    leadingColumn.frame(width: (availableWidth - 16) * 0.58)
                    trailingColumn.frame(width: (availableWidth - 16) * 0.42)
                }
            } else {
                leadingColumn
                trailingColumn
            }
            if !appearance.message.isEmpty { WorkNote(text: appearance.message) }
        }.frame(width: availableWidth, alignment: .leading)
    }
    private var leadingColumn: some View {
        VStack(alignment: .leading, spacing: 16) { themes; controlAudio; languageSettings }
    }
    private var trailingColumn: some View {
        VStack(alignment: .leading, spacing: 16) {
            OrbitalMoon().frame(height: 286).padding(18).background(TerminalGrid()).modifier(AppearanceRackSurface())
            menuAppearance
            notificationAudio
        }
    }
    private var themes: some View {
        VStack(alignment: .leading, spacing: 16) {
            panelHeading("01", title: "界面主题", code: "GUI CHROMATIC MATRIX")
            Text(L("三套电影主题，同步切换界面色彩与月相素材。"))
                .font(.system(size: 11)).foregroundStyle(TerminalStyle.muted).fixedSize(horizontal: false, vertical: true)
            HStack(spacing: 10) {
                TerminalIcon(name: "terminal", size: 19).foregroundStyle(TerminalStyle.accent)
                VStack(alignment: .leading, spacing: 5) {
                    Text("CURRENT ACTIVE RACK").font(TerminalStyle.mono(8)).foregroundStyle(TerminalStyle.muted)
                    Text(appearance.theme.title).font(.system(size: 16, weight: .semibold))
                }
                Spacer(minLength: 0)
            }.padding(12).background(TerminalStyle.recess)
            HStack(alignment: .top, spacing: 10) {
                themeCard(.dark, code: "TRON", icon: "moon", accent: Color(red: 0, green: 0.85, blue: 0.92),
                          preview: Color(red: 0.04, green: 0.08, blue: 0.11), detail: "深黑石墨底，青色控件与薄荷状态。")
                themeCard(.light, code: "ZIMA BLUE", icon: "sun.max", accent: Color(red: 0, green: 0.18, blue: 0.65),
                          preview: Color(red: 0.93, green: 0.95, blue: 0.97), detail: "银白仪器面板，克莱因蓝交互。")
                themeCard(.amber, code: "BLADE RUNNER 2049", icon: "scope", accent: Color(red: 1, green: 0.68, blue: 0.22),
                          preview: Color(red: 0.16, green: 0.11, blue: 0.05), detail: "深色雷达面板，琥珀色信号。")
            }
        }.padding(16).modifier(AppearanceRackSurface())
    }
    private func themeCard(_ theme: AppearanceController.Theme, code: String, icon: String, accent: Color, preview: Color, detail: String) -> some View {
        let selected = appearance.theme == theme
        return Button { appearance.theme = theme } label: {
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Text(selected ? "ACTIVE" : "AVAILABLE").font(TerminalStyle.mono(8))
                    Spacer(minLength: 0)
                    if selected { TerminalIcon(name: "checkmark", size: 10) }
                }.foregroundStyle(selected ? TerminalStyle.accent : TerminalStyle.muted)
                Text(theme.title).font(.system(size: 13, weight: .semibold)).foregroundStyle(TerminalStyle.ink)
                    .lineLimit(2).fixedSize(horizontal: false, vertical: true).frame(minHeight: 34, alignment: .topLeading)
                Text(code).font(TerminalStyle.mono(8)).foregroundStyle(TerminalStyle.muted)
                VStack(spacing: 16) {
                    TerminalIcon(name: icon, size: 29).foregroundStyle(accent).frame(height: 52)
                        .shadow(color: accent.opacity(0.28), radius: 10)
                    HStack(spacing: 4) {
                        Rectangle().fill(accent).frame(height: 3)
                        Rectangle().fill(accent.opacity(0.2)).frame(width: 16, height: 3)
                    }
                }.frame(maxWidth: .infinity).padding(12).background(preview).accessibilityHidden(true)
                Text(L(detail)).font(.system(size: 10)).foregroundStyle(TerminalStyle.muted)
                    .lineLimit(3).minimumScaleFactor(0.85).frame(height: 40, alignment: .topLeading)
            }.frame(maxWidth: .infinity, alignment: .leading).padding(10)
                .background(TerminalStyle.surface).overlay(Rectangle().strokeBorder(TerminalStyle.line.opacity(0.65)))
                .overlay(alignment: .top) { Rectangle().fill(selected ? TerminalStyle.accent : .clear).frame(height: 2) }
        }.buttonStyle(TerminalPlainButtonStyle()).workKeyboardFocus(radius: 0)
                .accessibilityLabel(theme.title).accessibilityValue(L(selected ? "已选择" : "未选择"))
            .accessibilityAddTraits(selected ? [.isSelected] : [])
    }
    private var controlAudio: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                panelHeading("02", title: "机械控件音效", code: "ACOUSTIC FEEDBACK")
                Spacer(minLength: 0)
                Toggle(L("机械控件音效"), isOn: $appearance.controlSounds).labelsHidden().toggleStyle(TerminalSwitchStyle())
            }
            Text(L("每次点击或切换只播放一声清脆短音，松开不再播放；只调整 Orexin 的控件音量。"))
                .font(.system(size: 11)).foregroundStyle(TerminalStyle.muted).fixedSize(horizontal: false, vertical: true)
            HStack {
                Text(L("声音方案 // CONTROL VOICE")).font(TerminalStyle.mono(9)).foregroundStyle(TerminalStyle.muted)
                Spacer(minLength: 8)
                TerminalPicker("控件声音方案", selection: Binding(get: { appearance.controlSound }, set: { preset in
                    appearance.controlSound = preset
                    ControlAudio.shared.preview(volume: appearance.controlVolume, preset: preset)
                }), choices: AppearanceController.ControlSound.allCases.map { TerminalChoice($0.title, $0) }, selectionSound: false)
                    .frame(width: 210)
            }
            Text(appearance.controlSound.detail).font(.system(size: 11)).foregroundStyle(TerminalStyle.muted)
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    TerminalLabel("控件音量 // GAIN LEVEL", systemImage: "speaker.wave.2").font(.system(size: 11))
                    Spacer(minLength: 0)
                    Text("\(Int(appearance.controlVolume * 100))%").font(TerminalStyle.mono(13)).foregroundStyle(TerminalStyle.accent)
                }
                TerminalSlider("控件音量", value: $appearance.controlVolume, in: 0...1)
                HStack {
                    ForEach([0, 25, 50, 75, 100], id: \.self) { percent in
                        if percent != 0 { Spacer(minLength: 0) }
                        Text("\(percent)%").font(TerminalStyle.mono(8)).foregroundStyle(TerminalStyle.muted)
                    }
                }
                HStack {
                    ForEach(AppearanceController.ControlSound.allCases) { preset in
                        Button { ControlAudio.shared.preview(volume: appearance.controlVolume, preset: preset) } label: {
                            TerminalLabel(String(preset.title.prefix(1)) + " " + L("试听"), systemImage: "play.fill")
                                .frame(maxWidth: .infinity)
                        }.buttonStyle(TerminalButtonStyle(sound: false)).workKeyboardFocus(radius: 0)
                            .accessibilityLabel(L("试听") + " " + preset.title).help(preset.detail)
                    }
                }
            }.padding(12).background(TerminalStyle.recess)
        }.padding(16).modifier(AppearanceRackSurface())
    }
    private var menuAppearance: some View {
        VStack(alignment: .leading, spacing: 13) {
            panelHeading("03", title: "菜单栏外观", code: "GLYPH CONFIG")
            Text(L("配置 macOS 菜单栏图标、时间格式与留白。")).font(.system(size: 10)).foregroundStyle(TerminalStyle.muted)
            HStack(spacing: 10) {
                Image(nsImage: appearance.menuImage()).resizable().scaledToFit().frame(width: 27, height: 27).accessibilityHidden(true)
                Text(L("图标")).font(.system(size: 11))
                Spacer(minLength: 0)
                TerminalPicker("菜单栏图标", selection: $appearance.icon,
                               choices: AppearanceController.Icon.allCases.map { TerminalChoice($0.title, $0) })
                    .labelsHidden().frame(width: 165)
            }.padding(10).background(TerminalStyle.recess)
            HStack {
                Text("PNG / JPEG / TIFF / ICNS").font(TerminalStyle.mono(8)).foregroundStyle(TerminalStyle.muted)
                Spacer(minLength: 0)
                Button(L("选择图标…"), action: appearance.chooseIcon).workKeyboardFocus(radius: 0)
            }
            if appearance.icon == .custom {
                configurationRow {
                    WorkToggle(title: "图标跟随系统明暗", detail: "关闭后保留原图颜色。", compact: true, isOn: $appearance.template)
                }
            }
            configurationRow {
                WorkToggle(title: "菜单栏显示结束时间", detail: "关闭时显示剩余时长。", compact: true, isOn: $appearance.showEndTime)
            }
            configurationRow { WorkToggle(title: "使用 24 小时制", compact: true, isOn: $appearance.twentyFourHour) }
            configurationRow {
                HStack(spacing: 6) {
                    Text(L("图标两侧留白")).font(.system(size: 11))
                    Spacer(minLength: 0)
                    Text("\(paddingPoints) pt").font(TerminalStyle.mono(10)).foregroundStyle(TerminalStyle.accent)
                    TerminalStepper("图标两侧留白", value: $appearance.iconPadding, in: 0...12).labelsHidden()
                }
            }
        }.padding(16).modifier(AppearanceRackSurface())
    }
    private var paddingPoints: Int { appearance.iconPadding.isFinite ? Int(min(12, max(0, appearance.iconPadding))) : 0 }
    private var notificationAudio: some View {
        VStack(alignment: .leading, spacing: 13) {
            panelHeading("04", title: "通知声音", code: "ALERT TONES")
            Text(appearance.soundName.isEmpty ? L("使用系统默认声音") : LF("已选择：%@", appearance.soundName))
                .font(.system(size: 10)).foregroundStyle(TerminalStyle.muted).fixedSize(horizontal: false, vertical: true)
            Text(L("支持短于 30 秒的 AIFF、WAV 或 CAF；通知权限仍由系统管理。"))
                .font(.system(size: 10)).foregroundStyle(TerminalStyle.muted).fixedSize(horizontal: false, vertical: true)
            HStack(spacing: 6) {
                Button(L("选择声音…"), action: appearance.chooseSound).workKeyboardFocus(radius: 0)
                Button(L("试听"), action: appearance.previewSound).workKeyboardFocus(radius: 0)
                Spacer(minLength: 0)
                Button(L("恢复默认"), action: appearance.resetSound).workKeyboardFocus(radius: 0)
            }
            configurationRow { WorkToggle(title: "通知时播放声音", compact: true, isOn: $notifier.notificationSound) }
            configurationRow { WorkToggle(title: "会话开始与结束播放声音", compact: true, isOn: $notifier.lifecycleSound) }
            configurationRow { WorkToggle(title: "延长会话时播放声音", compact: true, isOn: $notifier.extensionSound) }
        }.padding(16).modifier(AppearanceRackSurface())
    }
    private var languageSettings: some View {
        VStack(alignment: .leading, spacing: 14) {
            panelHeading("05", title: "界面语言", code: "DISPLAY LANGUAGE")
            Text(L("选择 Orexin 的界面语言。更改后立即生效。"))
                .font(.system(size: 11)).foregroundStyle(TerminalStyle.muted)
            HStack(spacing: 12) {
                Text(L("语言 // LANGUAGE")).font(TerminalStyle.mono(10)).foregroundStyle(TerminalStyle.muted)
                Spacer(minLength: 0)
                TerminalPicker("界面语言", selection: Binding(get: { languageID }, set: { selected in
                    languageID = selected
                    (NSApp.delegate as? AppDelegate)?.configureApplicationMenu()
                }),
                               choices: AppLanguage.allCases.map { TerminalChoice($0.name, $0.rawValue) })
                    .frame(width: 210)
            }
            Text(AppLanguage(rawValue: languageID)?.name ?? AppLanguage.simplifiedChinese.name)
                .font(TerminalStyle.mono(11)).foregroundStyle(TerminalStyle.accent)
        }.padding(16).modifier(AppearanceRackSurface())
    }
    private func panelHeading(_ number: String, title: String, code: String) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(number + " // " + L(title)).font(.system(size: 15, weight: .semibold)).accessibilityAddTraits(.isHeader)
            Text(code).font(TerminalStyle.mono(8)).tracking(0.5).foregroundStyle(TerminalStyle.muted)
        }
    }
    private func configurationRow<Content: View>(@ViewBuilder content: () -> Content) -> some View {
        content().padding(10).frame(maxWidth: .infinity, alignment: .leading).background(TerminalStyle.recess)
    }
}

private struct AppearanceRackSurface: ViewModifier {
    func body(content: Content) -> some View {
        content.frame(maxWidth: .infinity, alignment: .leading).background(TerminalStyle.surface)
            .overlay(Rectangle().strokeBorder(TerminalStyle.line.opacity(0.7)))
            .overlay(TerminalBrackets().stroke(TerminalStyle.line, lineWidth: 0.7).padding(5).allowsHitTesting(false))
    }
}
