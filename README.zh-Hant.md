<p align="center">
  <img src="Assets/README/cover.png" width="100%" alt="Orexin：深藍月蝕與琥珀色光弧。工作時保持喚醒，完成後適時休息。">
</p>

# Orexin

[简体中文](README.md) · **繁體中文** · [English](README.en.md) · [日本語](README.ja.md) · [Français](README.fr.md) · [Deutsch](README.de.md) · [Español](README.es.md)

[![Release](https://img.shields.io/github/v/release/Orxooo/Orexin?color=56d7df&label=release)](https://github.com/Orxooo/Orexin/releases/latest)
![macOS 15+](https://img.shields.io/badge/macOS-15%2B-8ba6b8)
[![CI](https://github.com/Orxooo/Orexin/actions/workflows/compatibility.yml/badge.svg?branch=main)](https://github.com/Orxooo/Orexin/actions/workflows/compatibility.yml)
[![GPL-3.0-only](https://img.shields.io/badge/license-GPL--3.0--only-b7c8d6)](LICENSE)

Orexin 是 macOS 選單列工具，用來控制 Mac 何時保持喚醒、何時允許睡眠。

編譯、下載、簡報或執行長時間任務時，可以選擇桌面或闔蓋工作，透過定時工作階段、自動規則和命令任務管理結束條件。

[下載最新版](https://github.com/Orxooo/Orexin/releases/latest) · [更新記錄](CHANGELOG.zh-Hant.md) · [使用手冊](https://github.com/Orxooo/Orexin/wiki)

![Orexin 工作模式頁面，創主題，畫面為簡體中文](Assets/README/orexin-1.0.3-modes.png)

## 功能

- **工作模式**：「後台工作」可防止闔蓋睡眠；「桌面工作」防止閒置睡眠，闔蓋時仍可睡眠。
- **螢幕控制**：亮度降至 0%、正常亮度、依系統設定時間關閉顯示器，或立即關閉顯示器。兩種工作模式會分別記住設定。
- **工作階段**：依持續時間、指定時間、應用程式或程序結束、下載完成等條件結束。
- **命令與執行計畫**：並行執行命令，查看結束代碼和日誌；用 JSON 編排相依關係、並行數量和失敗分支。
- **自動規則與設定**：依電源、顯示器、裝置、應用程式、網路或時間觸發；支援巢狀條件、試執行及設定匯入匯出。
- **保護與提醒**：可啟用低電量和高溫保護，查看服務異常、工作階段結束預告和更新提醒；支援系統通知與應用程式內彈出提示，更新由使用者手動安裝。

提供創、齊馬藍、銀翼殺手 2049 三套主題，支援簡體中文、繁體中文、英文、日文、法文、德文和西班牙文七種語言。詳細說明見[功能清單](FEATURES.md)。

## 開始使用

需要 **Apple Silicon Mac、macOS 15 或更新版本**。

1. 從[發布頁](https://github.com/Orxooo/Orexin/releases/latest)下載 Apple Silicon 安裝套件（檔名以 `-arm64.zip` 結尾），解壓縮並將 `Orexin.app` 放入「應用程式」。
2. 開啟應用程式，選擇工作模式和結束條件。闔蓋執行需要在「偏好設定」核准輔助服務。
3. 如需系統通知，請在「訊息提醒」中允許通知並傳送測試提醒。

安裝套件使用 **Apple Development 簽署，尚未完成 Developer ID 公證**。首次開啟遭阻擋時，請核對下載來源，再依 macOS「隱私權與安全性」提示操作，無需關閉 SIP 或全域 Gatekeeper。

將 ZIP 和發布頁的 `SHA256SUMS.txt` 放在同一目錄，即可驗證下載：

```sh
shasum -a 256 -c SHA256SUMS.txt
```

### 升級

等待命令和執行計畫完成，結束所有保持喚醒的請求，然後停止背景任務服務：

```sh
/Applications/Orexin.app/Contents/Helpers/orexin service-stop
```

再結束 Orexin，替換應用程式並重新開啟。若舊版沒有 `service-stop` 命令，可略過停止服務這一步。現有偏好設定、記錄和日誌會保留，舊任務不會重新執行。

### 使用注意事項

- 「工作時保持未鎖定」為選用設定，需個別授權。它會在本次工作期間關閉喚醒密碼要求，結束後恢復即時密碼保護；Orexin 不會儲存密碼，也不會解鎖已鎖定的 Mac。
- 亮度 0% 與關閉顯示器不同。依賴顯示器的螢幕截圖或介面自動化可能在顯示器關閉後受到影響。
- 恢復「正常休眠」模式只會釋放 Orexin 的保持喚醒請求，其他應用程式仍可能阻止睡眠。
- 高溫保護依據 macOS 的溫度壓力等級，不提供攝氏溫度；降溫後不會自動重新啟動已停止的工作。

## 任務管理與 CLI

背景命令和執行計畫可在結束介面後繼續執行；手動工作階段和自動規則需要介面程序持續執行。服務重新啟動後，未完成任務會標記為失聯，不會自動重新執行。

內建 CLI 位於應用程式套件中，無需另外安裝：

```sh
orexin=/Applications/Orexin.app/Contents/Helpers/orexin
"$orexin" service-start
"$orexin" run --title Build -- make
"$orexin" list --json
```

預設在命令結束後釋放該任務的保持喚醒請求。加上 `--after sleep`，可在成功後進入 60 秒睡眠倒數；所有時間重疊的請求都必須成功，且沒有其他工作階段或規則仍需要保持喚醒。釋放保持喚醒請求不會終止命令。

「工作時保持未鎖定」的授權需先在介面完成，CLI 不會顯示密碼視窗。參數、外部任務整合及計畫格式見 [CLI 指南](docs/CLI.md)與[執行計畫指南](docs/EXECUTION-PLANS.md)。

## 從原始碼建置

需要 **Xcode 26+、Swift 6**。

```sh
git clone https://github.com/Orxooo/Orexin.git
cd Orexin
swift test --arch arm64 --scratch-path /tmp/orexin-test-build
./scripts/build-app.sh
```

輸出為 `/tmp/orexin-dist/Orexin.app`，預設使用 ad hoc 簽署。闔蓋服務要求主程式和輔助服務使用相同的 Apple 開發者憑證：

```sh
OREXIN_SIGN_IDENTITY='憑證名稱或 SHA-1' ./scripts/build-app.sh
```

可用 `OREXIN_BUILD_DIR`、`OREXIN_OUTPUT_DIR` 指定建置與輸出目錄。CI 設定為 Xcode 26.3、macOS 15 / 26，執行結果見 [Actions](https://github.com/Orxooo/Orexin/actions/workflows/compatibility.yml)。

## 文件與意見回饋

- [工作設定](docs/WORK-CONFIGURATION.md) · [AppleScript 詞典](Resources/Orexin.sdef) · [安全說明](SECURITY.md)
- [回報問題](https://github.com/Orxooo/Orexin/issues/new/choose) · [討論](https://github.com/Orxooo/Orexin/discussions) · [私密漏洞回報](https://github.com/Orxooo/Orexin/security/advisories/new)
- [貢獻指南](CONTRIBUTING.md) · [行為準則](CODE_OF_CONDUCT.md)

本機記錄與日誌位於 `~/Library/Application Support/Orexin/`。舊 WakeMac 資料不會自動遷移或刪除，分享日誌前請檢查私人資訊。

## 授權

[GPL-3.0-only](LICENSE) · © 2026 Orxooo。第三方資源授權見 [NOTICE](NOTICE)。
