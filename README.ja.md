<p align="center">
  <img src="Assets/README/cover.png" width="100%" alt="Orexin：深い青の月食と琥珀色の光の弧。必要な間は起きて、時間になったら休む。">
</p>

# Orexin

[简体中文](README.zh-Hans.md) · [繁體中文](README.zh-Hant.md) · [English](README.md) · **日本語** · [Français](README.fr.md) · [Deutsch](README.de.md) · [Español](README.es.md)

[![リリース](https://img.shields.io/github/v/release/Orxooo/Orexin?color=56d7df&label=release)](https://github.com/Orxooo/Orexin/releases/latest)
![macOS 15+](https://img.shields.io/badge/macOS-15%2B-8ba6b8)
[![CI](https://github.com/Orxooo/Orexin/actions/workflows/compatibility.yml/badge.svg?branch=main)](https://github.com/Orxooo/Orexin/actions/workflows/compatibility.yml)
[![GPL-3.0-only](https://img.shields.io/badge/license-GPL--3.0--only-b7c8d6)](LICENSE)

Orexin は、Mac を起動状態に保つタイミングとスリープを許可するタイミングを管理する、macOS のメニューバーアプリです。

ビルド、ダウンロード、プレゼンテーション、長時間のタスクに合わせて、デスクトップでの作業や蓋を閉じた状態での作業を選べます。時間指定のセッション、自動ルール、コマンドタスクで、スリープ防止をいつ終了するか設定できます。

[最新版をダウンロード](https://github.com/Orxooo/Orexin/releases/latest) · [変更履歴](CHANGELOG.ja.md) · [利用ガイド](https://github.com/Orxooo/Orexin/wiki)

![トロンのテーマを使用した Orexin の作業モード画面。表示言語は簡体字中国語](Assets/README/orexin-1.0.3-modes.png)

## 機能

- **作業モード：**「バックグラウンド作業」は蓋を閉じたときのスリープを防ぎます。「デスクトップ作業」はアイドル時のスリープを防ぎ、蓋を閉じたときはスリープを許可します。
- **画面の制御：** 明るさを 0% にする、通常の明るさを保つ、システム設定の時間で画面を消す、すぐに画面を消す、のいずれかを選べます。設定は作業モードごとに記憶されます。
- **作業セッション：** 一定時間の経過、指定時刻、アプリやプロセスの終了、ダウンロードの完了などを条件に終了できます。
- **コマンドと実行プラン：** コマンドを並列実行し、終了コードやログを確認できます。JSON で依存関係、同時実行数の上限、失敗時の分岐を定義できます。
- **自動ルールとプロファイル：** 電源、ディスプレイ、デバイス、アプリ、ネットワーク、時刻を条件に作業を開始できます。条件の入れ子、試行実行、設定のインポートとエクスポートに対応します。
- **保護と通知：** バッテリー残量低下や熱負荷に対する保護を任意で有効にできます。サービスの異常、セッション終了の予告、アップデートの案内を、システム通知やアプリ内ポップアップで受け取れます。アップデートは手動でインストールします。

トロン、ジーマ・ブルー、ブレードランナー 2049 の 3 つのテーマを用意し、簡体字中国語、繁体字中国語、英語、日本語、フランス語、ドイツ語、スペイン語の 7 言語に対応しています。詳しくは[機能一覧](FEATURES.md)をご覧ください。

## 使い始める

<a id="系统要求"></a>

**Apple Silicon 搭載 Mac と macOS 15 以降**が必要です。

1. [リリースページ](https://github.com/Orxooo/Orexin/releases/latest)から Apple Silicon 用パッケージ（ファイル名の末尾が `-arm64.zip`）をダウンロードして展開し、`Orexin.app` を「アプリケーション」に移動します。
2. アプリを開き、作業モードと終了条件を選びます。蓋を閉じた状態で実行するには、「環境設定」でヘルパーサービスを承認する必要があります。
3. システム通知を受け取る場合は、「メッセージと通知」で通知を許可し、テスト通知を送信します。

パッケージは **Apple Development 証明書で署名されていますが、Developer ID による公証は未完了**です。初回起動がブロックされた場合は、ダウンロード元を確認したうえで、macOS の「プライバシーとセキュリティ」の案内に従ってください。SIP や Gatekeeper をシステム全体で無効にする必要はありません。

ダウンロードしたファイルを検証するには、ZIP とリリースページの `SHA256SUMS.txt` を同じディレクトリに置いて実行します。

```sh
shasum -a 256 -c SHA256SUMS.txt
```

### アップグレード

コマンドと実行プランが完了するのを待ち、すべてのスリープ防止要求を終了してから、バックグラウンドタスクサービスを停止します。

```sh
/Applications/Orexin.app/Contents/Helpers/orexin service-stop
```

続いて Orexin を終了し、アプリを置き換えて再度開きます。旧バージョンに `service-stop` コマンドがない場合は、サービスの停止手順を省略してください。既存の設定、履歴、ログは保持され、古いタスクが再実行されることはありません。

### 使用上の注意

- 「作業中はロックしない」は任意の設定で、個別の認証が必要です。今回の作業中はスリープ解除時のパスワード要求を無効にし、終了後はパスワードを即座に要求する設定に戻します。Orexin はパスワードを保存せず、ロック済みの Mac を解除することもありません。
- 明るさ 0% と画面の消灯は異なります。画面の状態に依存するスクリーンショットや UI 自動操作は、消灯によって影響を受ける場合があります。
- 「通常スリープ」に戻すと、Orexin のスリープ防止要求だけが解除されます。他のアプリが引き続きスリープを妨げる場合があります。
- 熱保護は macOS の熱負荷レベルに基づいて動作し、摂氏温度は表示しません。温度が下がっても、停止した作業は自動で再開しません。

## タスク管理と CLI

バックグラウンドのコマンドと実行プランは、Orexin の GUI を終了しても実行を続けます。手動セッションと自動ルールには、GUI プロセスが動作している必要があります。サービスの再起動後、未完了のタスクは接続喪失として記録され、自動では再実行されません。

CLI はアプリに同梱されており、別途インストールする必要はありません。

```sh
orexin=/Applications/Orexin.app/Contents/Helpers/orexin
"$orexin" service-start
"$orexin" run --title Build -- make
"$orexin" list --json
```

既定では、コマンドの終了後にそのタスクのスリープ防止要求を解除します。`--after sleep` を付けると、成功後にスリープまでの 60 秒間のカウントダウンを開始できます。同時期に重なる要求がすべて成功し、他のセッションやルールがスリープを防止していないことが条件です。スリープ防止要求を解除しても、コマンドは終了しません。

「作業中はロックしない」の認証は、あらかじめアプリの画面で済ませる必要があります。CLI ではパスワード入力画面を表示しません。オプション、外部タスクとの連携、プランの形式については、[CLI ガイド](docs/CLI.md)と[実行プランガイド](docs/EXECUTION-PLANS.md)をご覧ください。

## ソースからビルドする

**Xcode 26+ と Swift 6** が必要です。

```sh
git clone https://github.com/Orxooo/Orexin.git
cd Orexin
swift test --arch arm64 --scratch-path /tmp/orexin-test-build
./scripts/build-app.sh
```

出力先は `/tmp/orexin-dist/Orexin.app` で、既定ではアドホック署名を使用します。蓋を閉じた状態で動作させるには、アプリ本体とヘルパーサービスを同じ Apple 開発者証明書で署名する必要があります。

```sh
OREXIN_SIGN_IDENTITY='Certificate name or SHA-1' ./scripts/build-app.sh
```

`OREXIN_BUILD_DIR` と `OREXIN_OUTPUT_DIR` で、ビルド先と出力先のディレクトリを指定できます。CI は Xcode 26.3、macOS 15 / 26 を対象に設定されています。実行結果は [Actions](https://github.com/Orxooo/Orexin/actions/workflows/compatibility.yml) で確認できます。

## ドキュメントとフィードバック

- [作業プロファイル](docs/WORK-CONFIGURATION.md) · [AppleScript 辞書](Resources/Orexin.sdef) · [セキュリティについて](SECURITY.md)
- [問題を報告](https://github.com/Orxooo/Orexin/issues/new/choose) · [ディスカッション](https://github.com/Orxooo/Orexin/discussions) · [脆弱性を非公開で報告](https://github.com/Orxooo/Orexin/security/advisories/new)
- [貢献ガイド](CONTRIBUTING.md) · [行動規範](CODE_OF_CONDUCT.md)

ローカルの履歴とログは `~/Library/Application Support/Orexin/` に保存されます。旧 WakeMac のデータは、自動で移行・削除されません。ログを共有する前に、個人情報が含まれていないか確認してください。

## ライセンス

[GPL-3.0-only](LICENSE) · © 2026 Orxooo。サードパーティ製リソースのライセンスは [NOTICE](NOTICE) に記載しています。
