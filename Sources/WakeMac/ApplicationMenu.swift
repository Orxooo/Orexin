// SPDX-License-Identifier: GPL-3.0-only
// Copyright (c) 2026 Orxooo
import AppKit

extension AppDelegate {
    func configureApplicationMenu() {
        let main = NSMenu()
        func submenu(_ title: String) -> NSMenu {
            let item = NSMenuItem(title: L(title), action: nil, keyEquivalent: "")
            let menu = NSMenu(title: L(title)); item.submenu = menu; main.addItem(item); return menu
        }
        func item(_ menu: NSMenu, _ title: String, _ action: Selector, _ key: String = "", target: AnyObject? = nil) {
            let item = NSMenuItem(title: L(title), action: action, keyEquivalent: key); item.target = target; menu.addItem(item)
        }
        let application = submenu("Orexin")
        item(application, "关于 Orexin", #selector(openAboutSoftware), target: self)
        application.addItem(.separator())
        item(application, "偏好设置…", #selector(openMainWindow), ",", target: self)
        let services = NSMenuItem(title: L("服务"), action: nil, keyEquivalent: ""); services.submenu = NSMenu(); application.addItem(services); NSApp.servicesMenu = services.submenu
        application.addItem(.separator())
        item(application, "隐藏 Orexin", #selector(NSApplication.hide(_:)), "h", target: NSApp)
        item(application, "显示全部", #selector(NSApplication.unhideAllApplications(_:)), target: NSApp)
        application.addItem(.separator())
        item(application, "退出 Orexin", #selector(quit), "q", target: self)
        let file = submenu("文件")
        item(file, "打开主窗口", #selector(openMainWindow), "1", target: self)
        item(file, "打开快捷面板", #selector(showPanel), "2", target: self)
        file.addItem(.separator())
        item(file, "关闭窗口", #selector(NSWindow.performClose(_:)), "w")
        let edit = submenu("编辑")
        item(edit, "撤销", Selector(("undo:")), "z")
        let redo = NSMenuItem(title: L("重做"), action: Selector(("redo:")), keyEquivalent: "z"); redo.keyEquivalentModifierMask = [.command, .shift]; edit.addItem(redo)
        edit.addItem(.separator())
        item(edit, "剪切", #selector(NSText.cut(_:)), "x")
        item(edit, "复制", #selector(NSText.copy(_:)), "c")
        item(edit, "粘贴", #selector(NSText.paste(_:)), "v")
        item(edit, "全选", #selector(NSText.selectAll(_:)), "a")
        let window = submenu("窗口")
        item(window, "最小化", #selector(NSWindow.performMiniaturize(_:)), "m")
        item(window, "缩放", #selector(NSWindow.performZoom(_:)))
        window.addItem(.separator())
        item(window, "全部置于最前", #selector(NSApplication.arrangeInFront(_:)), target: NSApp)
        NSApp.windowsMenu = window
        let help = submenu("帮助")
        item(help, "查看温度保护", #selector(openTemperatureProtection), target: self)
        NSApp.helpMenu = help
        NSApp.mainMenu = main
    }
    @objc private func openMainWindow() { showPreferences() }
    @objc private func openAboutSoftware() {
        showPreferences(); NotificationCenter.default.post(name: .orexinOpenAbout, object: nil)
    }
    @objc private func openTemperatureProtection() {
        showPreferences(); NotificationCenter.default.post(name: .wakeMacOpenTemperature, object: nil)
    }
}
