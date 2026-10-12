#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-3.0-only
# Copyright (c) 2026 Orxooo
"""Keep core power terminology consistent after on-device draft translation."""
import json
import re
import subprocess
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent / "Resources" / "Localization"
translations = {
    "en": {
        "工作模式": "Work Modes", "工作会话": "Work Session", "自动触发": "Auto Triggers",
        "自动收尾": "Automatic Wrap-up", "命令任务": "Command Tasks", "偏好设置": "Preferences",
        "温度保护": "Thermal Protection", "主题外观": "Appearance", "运行记录": "Activity Log",
        "关于软件": "About Orexin", "后台工作": "Background Work", "桌面工作": "Desktop Work",
        "正常休眠": "Normal Sleep", "保持唤醒": "Keep Awake", "合盖继续运行": "Keep Running with Lid Closed",
        "允许屏幕自动关闭": "Allow Automatic Display Sleep", "软件更新": "Software Updates",
        "检查更新": "Check for Updates", "界面语言": "Language",
        "低电量休眠倒计时": "Low Battery Sleep Countdown",
        "创:电子世界争霸战": "TRON: Legacy", "齐马蓝": "Zima Blue", "银翼杀手2049": "Blade Runner 2049",
        "跟随系统": "Follow System", "已授权": "Authorized", "未授权": "Not Authorized",
        "试听": "Preview",
        "后台": "Background", "桌面": "Desktop", "正常": "Normal", "未知": "Unknown",
        "切换中": "Switching", "待处理": "Action Needed",
    },
    "ja": {
        "工作模式": "作業モード", "工作会话": "作業セッション", "自动触发": "自動トリガー",
        "自动收尾": "自動終了", "命令任务": "コマンドタスク", "偏好设置": "環境設定",
        "温度保护": "熱保護", "主题外观": "テーマと外観", "运行记录": "動作履歴",
        "关于软件": "Orexin について", "后台工作": "バックグラウンド作業", "桌面工作": "デスクトップ作業",
        "正常休眠": "通常スリープ", "保持唤醒": "スリープを防ぐ", "合盖继续运行": "閉じたまま動作",
        "允许屏幕自动关闭": "ディスプレイの自動スリープを許可", "软件更新": "ソフトウェアアップデート",
        "检查更新": "アップデートを確認", "界面语言": "表示言語",
        "低电量休眠倒计时": "低バッテリー時のスリープまでのカウントダウン",
        "创:电子世界争霸战": "トロン：レガシー", "齐马蓝": "ジーマ・ブルー", "银翼杀手2049": "ブレードランナー 2049",
        "跟随系统": "システム設定に合わせる", "已授权": "許可済み", "未授权": "未許可",
        "试听": "試聴",
        "后台": "バックグラウンド", "桌面": "デスクトップ", "正常": "通常", "未知": "不明",
        "切换中": "切り替え中", "待处理": "要確認",
    },
    "fr": {
        "工作模式": "Modes de travail", "工作会话": "Session de travail", "自动触发": "Déclencheurs automatiques",
        "自动收尾": "Fin automatique", "命令任务": "Tâches de commande", "偏好设置": "Préférences",
        "温度保护": "Protection thermique", "主题外观": "Thèmes et apparence", "运行记录": "Journal d’activité",
        "关于软件": "À propos d’Orexin", "后台工作": "Travail en arrière-plan", "桌面工作": "Travail sur le bureau",
        "正常休眠": "Veille normale", "保持唤醒": "Maintenir éveillé", "合盖继续运行": "Continuer à fonctionner capot fermé",
        "允许屏幕自动关闭": "Autoriser la mise en veille de l’écran", "软件更新": "Mises à jour",
        "检查更新": "Rechercher des mises à jour", "界面语言": "Langue de l’interface",
        "低电量休眠倒计时": "Compte à rebours de veille pour batterie faible",
        "创:电子世界争霸战": "Tron : L’Héritage", "齐马蓝": "Zima Blue", "银翼杀手2049": "Blade Runner 2049",
        "跟随系统": "Suivre le système", "已授权": "Autorisé", "未授权": "Non autorisé",
        "试听": "Écouter",
        "后台": "Arrière-plan", "桌面": "Bureau", "正常": "Normal", "未知": "Inconnu",
        "切换中": "Changement en cours", "待处理": "Action requise",
    },
    "de": {
        "工作模式": "Arbeitsmodi", "工作会话": "Arbeitssitzung", "自动触发": "Automatische Auslöser",
        "自动收尾": "Automatischer Abschluss", "命令任务": "Befehlsaufgaben", "偏好设置": "Einstellungen",
        "温度保护": "Wärmeschutz", "主题外观": "Design und Darstellung", "运行记录": "Aktivitätsprotokoll",
        "关于软件": "Über Orexin", "后台工作": "Hintergrundarbeit", "桌面工作": "Arbeit am Schreibtisch",
        "正常休眠": "Normaler Ruhezustand", "保持唤醒": "Ruhezustand verhindern", "合盖继续运行": "Bei geschlossenem Deckel weiterarbeiten",
        "允许屏幕自动关闭": "Automatischen Display-Ruhezustand erlauben", "软件更新": "Softwareupdates",
        "检查更新": "Nach Updates suchen", "界面语言": "Sprache",
        "低电量休眠倒计时": "Ruhezustands-Countdown bei niedrigem Akkustand",
        "创:电子世界争霸战": "Tron: Legacy", "齐马蓝": "Zima Blue", "银翼杀手2049": "Blade Runner 2049",
        "跟随系统": "Systemeinstellung übernehmen", "已授权": "Autorisiert", "未授权": "Nicht autorisiert",
        "试听": "Probehören",
        "后台": "Hintergrund", "桌面": "Schreibtisch", "正常": "Normal", "未知": "Unbekannt",
        "切换中": "Wechsel läuft", "待处理": "Handlung erforderlich",
    },
    "es": {
        "工作模式": "Modos de trabajo", "工作会话": "Sesión de trabajo", "自动触发": "Activadores automáticos",
        "自动收尾": "Cierre automático", "命令任务": "Tareas de comandos", "偏好设置": "Preferencias",
        "温度保护": "Protección térmica", "主题外观": "Temas y apariencia", "运行记录": "Registro de actividad",
        "关于软件": "Acerca de Orexin", "后台工作": "Trabajo en segundo plano", "桌面工作": "Trabajo en el escritorio",
        "正常休眠": "Reposo normal", "保持唤醒": "Mantener activo", "合盖继续运行": "Seguir funcionando con la tapa cerrada",
        "允许屏幕自动关闭": "Permitir el reposo automático de la pantalla", "软件更新": "Actualizaciones",
        "检查更新": "Buscar actualizaciones", "界面语言": "Idioma de la interfaz",
        "低电量休眠倒计时": "Cuenta atrás para el reposo por batería baja",
        "创:电子世界争霸战": "Tron: El legado", "齐马蓝": "Zima Blue", "银翼杀手2049": "Blade Runner 2049",
        "跟随系统": "Seguir el sistema", "已授权": "Autorizado", "未授权": "Sin autorizar",
        "试听": "Escuchar",
        "后台": "Segundo plano", "桌面": "Escritorio", "正常": "Normal", "未知": "Desconocido",
        "切换中": "Cambiando", "待处理": "Acción necesaria",
    },
    "zh-Hant": {
        "偏好设置": "偏好設定", "运行记录": "執行紀錄", "关于软件": "關於 Orexin",
        "软件更新": "軟體更新", "检查更新": "檢查更新", "界面语言": "介面語言",
        "自动收尾": "自動收尾", "工作会话": "工作階段", "桌面工作": "桌面工作",
        "合盖继续运行": "闔上螢幕後繼續執行", "允许屏幕自动关闭": "允許螢幕自動關閉",
    },
}


# Reviewed product terminology and runtime format strings. Keep technical tokens
# unchanged, and use session/sleep/lid terminology rather than literal machine drafts.
reviewed_ui = {
    "网站与赞助": ["網站與贊助", "Website & Sponsorship", "ウェブサイトと支援", "Site et soutien", "Website und Unterstützung", "Sitio web y apoyo"],
    "官方网站": ["官方網站", "Official Website", "公式サイト", "Site officiel", "Offizielle Website", "Sitio oficial"],
    "支持项目": ["支持專案", "Support the Project", "プロジェクトを支援", "Soutenir le projet", "Projekt unterstützen", "Apoyar el proyecto"],
    "即将提供": ["即將提供", "Coming Soon", "近日公開", "Bientôt disponible", "Demnächst verfügbar", "Próximamente"],
    "会话设置": ["工作階段設定", "Session Settings", "セッション設定", "Paramètres de session", "Sitzungseinstellungen", "Ajustes de sesión"],
    "会话效果": ["工作階段效果", "Session Effects", "セッションの動作", "Effets de session", "Sitzungsverhalten", "Efectos de sesión"],
    "会话记录": ["工作階段紀錄", "Session Events", "セッション履歴", "Événements de session", "Sitzungsereignisse", "Eventos de sesión"],
    "当前会话状态": ["目前工作階段狀態", "Current Session", "現在のセッション", "Session actuelle", "Aktuelle Sitzung", "Sesión actual"],
    "会话尚未开始。": ["工作階段尚未開始。", "No session has started.", "セッションは開始されていません。", "Aucune session en cours.", "Keine Sitzung gestartet.", "No hay una sesión activa."],
    "开始会话": ["開始工作階段", "Start Session", "セッションを開始", "Démarrer la session", "Sitzung starten", "Iniciar sesión de trabajo"],
    "结束会话": ["結束工作階段", "End Session", "セッションを終了", "Terminer la session", "Sitzung beenden", "Finalizar sesión de trabajo"],
    "开始时使用": ["開始時使用", "Starting Mode", "開始時のモード", "Mode de départ", "Startmodus", "Modo inicial"],
    "结束条件": ["結束條件", "End Condition", "終了条件", "Condition de fin", "Endbedingung", "Condición de fin"],
    "其他结束条件": ["其他結束條件", "Other End Conditions", "その他の終了条件", "Autres conditions de fin", "Weitere Endbedingungen", "Otras condiciones de fin"],
    "指定时间 / 单个进程": ["指定時間 / 單一程序", "Time / Process", "指定時刻 / プロセス", "Heure / Processus", "Zeit / Prozess", "Hora / Proceso"],
    "手动结束": ["手動結束", "Manual", "手動終了", "Manuelle", "Manuell", "Manual"],
    "保持至手动切换": ["維持至手動切換", "Continue until you end it", "手動で終了するまで継続", "Continuer jusqu’à l’arrêt manuel", "Bis zum manuellen Ende", "Continuar hasta finalizar manualmente"],
    "定时持续": ["定時持續", "Duration", "指定時間", "Durée", "Dauer", "Duración"],
    "到时恢复正常休眠": ["到時恢復正常休眠", "Restore normal sleep when time is up", "時間が来たら通常スリープに戻る", "Rétablir la veille à la fin", "Danach normalen Ruhezustand zulassen", "Restaurar el reposo al terminar"],
    "应用退出": ["應用程式結束", "App Exit", "アプリ終了", "Fermeture d’app", "App beendet", "Cierre de app"],
    "监测所选应用退出": ["監測所選應用程式結束", "Wait for the selected app to quit", "選択したアプリの終了を待つ", "Attendre la fermeture de l’app", "Auf Ende der gewählten App warten", "Esperar a que cierre la app elegida"],
    "下载完成": ["下載完成", "Download Complete", "ダウンロード完了", "Téléchargement fini", "Download fertig", "Descarga completa"],
    "观察文件增长与稳定": ["觀察檔案增長與穩定", "Monitor file growth and stability", "ファイルの増加と安定を監視", "Surveiller la taille et sa stabilité", "Dateiwachstum und Stabilität prüfen", "Observar el tamaño y su estabilidad"],
    "快速持续时间设定": ["快速持續時間設定", "Duration Presets", "時間プリセット", "Durées prédéfinies", "Zeitvorgaben", "Duraciones predefinidas"],
    "保持工作状态，直到你结束会话或手动切换模式。": ["維持工作狀態，直到你結束工作階段或手動切換模式。", "Keep working until you end the session or switch modes.", "セッションを終了するかモードを切り替えるまで作業を継続します。", "Continuer jusqu’à la fin de session ou au changement de mode.", "Weiterarbeiten, bis die Sitzung endet oder der Modus gewechselt wird.", "Continuar hasta finalizar la sesión o cambiar de modo."],
    "保持工作 · 允许屏幕关闭": ["維持工作 · 允許螢幕關閉", "Keep tasks running · Allow display sleep", "作業を継続 · 画面スリープを許可", "Continuer les tâches · Écran en veille autorisé", "Aufgaben fortsetzen · Display darf ruhen", "Mantener tareas · Permitir reposo de pantalla"],
    "合盖保活": ["闔蓋後繼續執行", "Keep running with lid closed", "蓋を閉じても動作", "Continuer capot fermé", "Bei geschlossenem Deckel weiterarbeiten", "Seguir con la tapa cerrada"],
    "合盖服务": ["闔蓋服務", "Lid Service", "クラムシェルサービス", "Service capot fermé", "Dienst für geschlossenen Deckel", "Servicio de tapa cerrada"],
    "合盖运行特权服务": ["闔蓋執行特權服務", "Privileged Lid Service", "クラムシェル動作サービス", "Service privilégié capot fermé", "Privilegierter Dienst für geschlossenen Deckel", "Servicio privilegiado de tapa cerrada"],
    "合盖服务已安装": ["闔蓋服務已安裝", "Lid Service Installed", "サービスをインストール済み", "Service installé", "Dienst installiert", "Servicio instalado"],
    "合盖服务已授权，可以选择后台工作。": ["闔蓋服務已授權，可以選擇背景工作。", "Lid service authorized. Background Work is available.", "サービスは許可済みです。バックグラウンド作業を使用できます。", "Service autorisé. Le travail en arrière-plan est disponible.", "Dienst autorisiert. Hintergrundarbeit ist verfügbar.", "Servicio autorizado. El trabajo en segundo plano está disponible."],
    "切换回正常模式或退出应用会恢复休眠；异常断线和心跳超时由服务自动恢复。": ["切換回正常模式或結束應用程式會恢復休眠；連線中斷和心跳逾時由服務自動恢復。", "Normal Sleep or quitting releases the sleep inhibitor. The service also releases it after a disconnect or heartbeat timeout.", "通常スリープへの切り替えやアプリ終了でスリープ抑止を解除します。切断やハートビートのタイムアウト時も自動解除します。", "La veille normale ou la fermeture libère le blocage de veille. Le service le libère aussi après une déconnexion ou un délai de heartbeat dépassé.", "Normaler Ruhezustand und Beenden geben die Schlafsperre frei. Der Dienst gibt sie auch bei Verbindungsabbruch oder Heartbeat-Timeout frei.", "Reposo normal o salir libera el bloqueo de reposo. El servicio también lo libera tras una desconexión o un heartbeat agotado."],
    "日常使用偏好": ["日常使用偏好", "Everyday Preferences", "日常の設定", "Préférences d’utilisation", "Allgemeine Einstellungen", "Preferencias de uso"],
    "锁屏与密码策略": ["鎖定與密碼策略", "Lock & Password Policy", "ロックとパスワード", "Verrouillage et mot de passe", "Sperre und Passwort", "Bloqueo y contraseña"],
    "要求即时密码保护": ["立即要求密碼", "Require Password Immediately", "すぐにパスワードを要求", "Exiger le mot de passe immédiatement", "Passwort sofort verlangen", "Exigir contraseña inmediatamente"],
    "打开系统设置": ["開啟系統設定", "Open System Settings", "システム設定を開く", "Ouvrir Réglages Système", "Systemeinstellungen öffnen", "Abrir Ajustes del Sistema"],
    "打开系统锁屏设置": ["開啟系統鎖定設定", "Open Lock Screen Settings", "ロック画面の設定を開く", "Réglages de l’écran verrouillé", "Sperrbildschirm öffnen", "Abrir ajustes de bloqueo"],
    "移除服务": ["移除服務", "Remove Service", "サービスを削除", "Supprimer le service", "Dienst entfernen", "Eliminar servicio"],
    "界面主题": ["介面主題", "Interface Theme", "テーマ", "Thème de l’interface", "Oberflächenthema", "Tema de interfaz"],
    "机械控件音效": ["機械控制音效", "Control Sounds", "操作音", "Sons des commandes", "Bedientöne", "Sonidos de controles"],
    "温度保护已就绪": ["溫度保護已就緒", "Thermal Protection Ready", "熱保護は準備完了", "Protection thermique prête", "Wärmeschutz bereit", "Protección térmica lista"],
    "系统压力等级": ["系統壓力等級", "System Thermal Level", "システムの熱負荷", "Niveau thermique système", "Thermische Systembelastung", "Nivel térmico del sistema"],
    "达到保护阈值": ["達到保護閾值", "Protection Threshold Reached", "保護しきい値に到達", "Seuil de protection atteint", "Schutzschwelle erreicht", "Umbral de protección alcanzado"],
    "正在重试释放": ["正在重試釋放", "Retrying Release", "解除を再試行中", "Nouvelle tentative de libération", "Freigabe wird erneut versucht", "Reintentando liberación"],
    "轻度": ["輕度", "Moderate", "軽度", "Modérée", "Mäßig", "Moderado"],
    "严重": ["嚴重", "Serious", "高負荷", "Élevée", "Hoch", "Grave"],
    "危急": ["危急", "Critical", "危険", "Critique", "Kritisch", "Crítico"],
    "轻度压力": ["輕度壓力", "Moderate", "軽度", "Modérée", "Mäßig", "Moderado"],
    "严重压力": ["嚴重壓力", "Serious", "高負荷", "Élevée", "Hoch", "Grave"],
    "危急压力": ["危急壓力", "Critical", "危険", "Critique", "Kritisch", "Crítico"],
    "正常休眠": ["正常休眠", "Normal Sleep", "通常スリープ", "Veille normale", "Normaler Ruhezustand", "Reposo normal"],
    "按 macOS 报告的温度压力等级执行保护。系统未提供摄氏温度读数。": ["依 macOS 回報的溫度壓力等級執行保護。系統未提供攝氏溫度讀數。", "Protection uses the thermal level reported by macOS. A temperature in degrees Celsius is not available.", "macOS が報告する熱負荷レベルに基づいて保護します。摂氏温度は取得できません。", "La protection utilise le niveau thermique signalé par macOS. La température en degrés Celsius n’est pas disponible.", "Der Schutz verwendet die von macOS gemeldete thermische Belastung. Ein Celsius-Messwert ist nicht verfügbar.", "La protección usa el nivel térmico indicado por macOS. No hay una lectura en grados Celsius."],
    "正在执行的命令继续运行；不会强制休眠或关闭其他任务。降温后由你重新开启工作。": ["正在執行的命令會繼續；不會強制休眠或關閉其他工作。降溫後請重新開啟工作。", "Running commands continue. Orexin does not force sleep or close other tasks. Restart work mode after the Mac cools down.", "実行中のコマンドは継続します。強制スリープや他のタスクの終了は行いません。冷却後に作業モードを再開してください。", "Les commandes continuent. Orexin ne force pas la veille et ne ferme pas d’autres tâches. Relancez le mode de travail après refroidissement.", "Laufende Befehle werden fortgesetzt. Orexin erzwingt keinen Ruhezustand und beendet keine anderen Aufgaben. Nach dem Abkühlen den Arbeitsmodus neu starten.", "Los comandos continúan. Orexin no fuerza el reposo ni cierra otras tareas. Reinicia el modo de trabajo cuando el Mac se enfríe."],
    "温度保护": ["溫度保護", "Thermal Protection", "熱保護", "Protection thermique", "Wärmeschutz", "Protección térmica"],
    "监测系统温度压力，在过热时释放保活。": ["監測系統溫度壓力，過熱時解除防休眠。", "Monitor thermal pressure and release sleep inhibitors when overheating.", "熱負荷を監視し、過熱時にスリープ抑止を解除します。", "Surveiller la pression thermique et libérer les blocages de veille en cas de surchauffe.", "Thermische Belastung überwachen und bei Überhitzung Schlafsperren freigeben.", "Vigilar la presión térmica y liberar los bloqueos de reposo al sobrecalentarse."],
    "已接电源": ["已接電源", "Connected to Power", "電源に接続", "Sur secteur", "Netzbetrieb", "Conectado a corriente"],
    "已连接电源": ["已連接電源", "Connected to Power", "電源に接続", "Sur secteur", "Netzbetrieb", "Conectado a corriente"],
    "电池供电": ["電池供電", "On Battery", "バッテリー駆動", "Sur batterie", "Akkubetrieb", "Con batería"],
    "待采样": ["待取樣", "Awaiting Sample", "サンプル待ち", "Échantillon en attente", "Messung ausstehend", "Esperando muestra"],
    "电池剩余 %d%%": ["電池剩餘 %d%%", "Battery: %d%%", "バッテリー残量：%d%%", "Batterie : %d%%", "Akku: %d%%", "Batería: %d%%"],
    "%@ 分钟": ["%@ 分鐘", "%@ min", "%@ 分", "%@ min", "%@ Min.", "%@ min"],
    "%d 分钟": ["%d 分鐘", "%d min", "%d 分", "%d min", "%d Min.", "%d min"],
    "电池供电且电量达到 %d%% 时，留出 60 秒取消后请求休眠。": ["使用電池且電量達 %d%% 時，保留 60 秒取消，再要求休眠。", "On battery at %d%%, allow 60 seconds to cancel before requesting sleep.", "バッテリー残量が %d%% になると、60 秒間のキャンセル猶予後にスリープを要求します。", "Sur batterie à %d%%, laisser 60 secondes pour annuler avant la veille.", "Bei Akkubetrieb und %d%% bleiben 60 Sekunden zum Abbrechen vor dem Ruhezustand.", "Con batería al %d%%, hay 60 segundos para cancelar antes del reposo."],
    "达到%@温度压力时，释放 Orexin 的防休眠断言、合盖保活和会话效果，并取消自动休眠倒计时。": ["達到%@溫度壓力時，解除 Orexin 的防休眠、闔蓋保活和工作階段效果，並取消自動休眠倒數。", "At the %@ thermal level, release Orexin’s sleep and lid inhibitors and session effects, and cancel pending sleep countdowns.", "熱負荷が「%@」に達すると、スリープ・クラムシェル抑止とセッション効果を解除し、スリープのカウントダウンを取り消します。", "Au niveau thermique %@, libérer les blocages de veille et de capot, les effets de session et annuler les comptes à rebours.", "Bei thermischer Belastung %@ Schlaf- und Deckelsperren sowie Sitzungseffekte freigeben und Schlaf-Countdowns abbrechen.", "En el nivel térmico %@, liberar los bloqueos de reposo y tapa y los efectos de sesión, y cancelar las cuentas atrás."],
    "启用后，": ["啟用後，", "When enabled: ", "有効な場合：", "Si activé : ", "Wenn aktiviert: ", "Si se activa: "],
    "模式已核验：": ["模式已驗證：", "Mode verified: ", "モード確認済み：", "Mode vérifié : ", "Modus bestätigt: ", "Modo verificado: "],
    "切换模式：": ["切換模式：", "Switching mode: ", "モード切り替え：", "Changement de mode : ", "Moduswechsel: ", "Cambiando modo: "],
    "检测到屏幕亮起。": ["偵測到螢幕亮起。", "Display turned on.", "画面が点灯しました。", "Écran allumé.", "Display eingeschaltet.", "Pantalla encendida."],
    "检测到屏幕熄灭。": ["偵測到螢幕熄滅。", "Display turned off.", "画面が消灯しました。", "Écran éteint.", "Display ausgeschaltet.", "Pantalla apagada."],
    "系统显示器已唤醒。": ["系統顯示器已喚醒。", "System display woke.", "システム画面が復帰しました。", "Écran système réveillé.", "Systemdisplay aufgewacht.", "Pantalla del sistema activada."],
    "系统显示器已休眠。": ["系統顯示器已休眠。", "System display entered sleep.", "システム画面がスリープしました。", "Écran système en veille.", "Systemdisplay im Ruhezustand.", "Pantalla del sistema en reposo."],
    "合盖继续工作，允许屏幕自动关闭。": ["闔蓋後繼續工作，允許螢幕自動關閉。", "Keep tasks running with the lid closed; allow display sleep.", "蓋を閉じても作業を継続し、画面のスリープを許可します。", "Continuer capot fermé ; autoriser la veille de l’écran.", "Bei geschlossenem Deckel weiterarbeiten; Display-Ruhezustand zulassen.", "Continuar con la tapa cerrada; permitir el reposo de pantalla."],
    "保持桌面工作，合盖后允许休眠。": ["維持桌面工作，闔蓋後允許休眠。", "Keep desktop tasks running; allow sleep when the lid closes.", "デスクトップ作業を継続し、蓋を閉じるとスリープを許可します。", "Continuer les tâches ; autoriser la veille à la fermeture du capot.", "Desktop-Aufgaben fortsetzen; beim Zuklappen Ruhezustand zulassen.", "Mantener tareas de escritorio; permitir reposo al cerrar la tapa."],
    "释放保活，恢复系统自然休眠。": ["解除防休眠，恢復系統自然休眠。", "Release sleep inhibitors and restore normal system sleep.", "スリープ抑止を解除し、通常のスリープ動作に戻します。", "Libérer les blocages et rétablir la veille normale.", "Schlafsperren freigeben und normalen Ruhezustand wiederherstellen.", "Liberar bloqueos y restaurar el reposo normal del sistema."],
    "∞  无限": ["∞ 無限", "∞ Unlimited", "∞ 無制限", "∞ Illimitée", "∞ Unbegrenzt", "∞ Sin límite"],
    "∞ 无限": ["∞ 無限", "∞ Unlimited", "∞ 無制限", "∞ Illimitée", "∞ Unbegrenzt", "∞ Sin límite"],
    "主题外观": ["主題外觀", "Appearance", "テーマと外観", "Apparence", "Darstellung", "Apariencia"],
    "运行记录": ["執行紀錄", "Activity Log", "動作履歴", "Journal d’activité", "Aktivitätslog", "Registro de actividad"],
    "命令任务": ["命令工作", "Command Tasks", "コマンドタスク", "Commandes", "Befehlsaufgaben", "Tareas de comandos"],
    "自动触发": ["自動觸發", "Auto Triggers", "自動トリガー", "Déclencheurs", "Auto-Auslöser", "Activadores"],
}

reviewed_ui.update({
    "工作时保持未锁定": ["工作時保持未鎖定", "Keep Unlocked While Working", "作業中はロックしない", "Rester déverrouillé pendant le travail", "Während der Arbeit entsperrt bleiben", "Mantener desbloqueado al trabajar"],
    "授权本次工作保持未锁定": ["授權本次工作保持未鎖定", "Authorize Unlocked Work", "今回の作業でロックを無効にする", "Autoriser le travail déverrouillé", "Entsperrtes Arbeiten autorisieren", "Autorizar trabajo desbloqueado"],
    "授权本次工作": ["授權本次工作", "Authorize This Work Session", "今回の作業を許可", "Autoriser cette session", "Diese Arbeitssitzung autorisieren", "Autorizar esta sesión de trabajo"],
    "Mac 账户密码": ["Mac 帳號密碼", "Mac Account Password", "Mac アカウントのパスワード", "Mot de passe du compte Mac", "Passwort des Mac-Kontos", "Contraseña de la cuenta del Mac"],
    "开始工作时输入一次 Mac 密码。熄屏或合盖时保持未锁定；工作结束后自动恢复即时密码保护。需要已授权的系统服务。": ["開始工作時輸入一次 Mac 密碼。熄屏或闔蓋時保持未鎖定；工作結束後自動恢復立即要求密碼。需要已授權的系統服務。", "Enter your Mac password when starting work. Display sleep and lid closure stay unlocked; ending work restores immediate password protection. Requires the authorized system service.", "作業開始時に Mac のパスワードを入力します。画面スリープや蓋を閉じてもロックせず、終了時に即時のパスワード保護に戻します。許可済みのシステムサービスが必要です。", "Saisissez votre mot de passe Mac au début du travail. L’écran en veille et le capot fermé restent déverrouillés ; la fin rétablit la protection immédiate. Le service système doit être autorisé.", "Beim Arbeitsbeginn das Mac-Passwort eingeben. Display-Ruhezustand und Zuklappen bleiben entsperrt; das Arbeitsende stellt sofortigen Passwortschutz wieder her. Der Systemdienst muss autorisiert sein.", "Introduce tu contraseña del Mac al empezar. La pantalla en reposo y la tapa cerrada permanecen desbloqueadas; al terminar se restaura la protección inmediata. Requiere el servicio autorizado."],
    "熄屏或合盖后无需密码即可返回桌面，附近的人也能访问这台 Mac。输入 Mac 账户密码以授权本次工作；Orexin 不保存密码。工作结束后自动恢复即时密码保护。": ["熄屏或闔蓋後不需密碼即可返回桌面，附近的人也能存取這台 Mac。輸入 Mac 帳號密碼授權本次工作；Orexin 不儲存密碼。工作結束後自動恢復立即要求密碼。", "Anyone nearby can access this Mac after display sleep or lid closure without a password. Enter your Mac account password to authorize this work session. Orexin does not save it. Ending work restores immediate password protection.", "画面スリープや蓋を閉じた後もパスワードなしでデスクトップに戻れるため、近くの人もこの Mac にアクセスできます。今回の作業を許可するため Mac のパスワードを入力してください。Orexin は保存しません。終了時に即時のパスワード保護に戻します。", "Après la veille de l’écran ou la fermeture du capot, toute personne à proximité peut accéder au Mac sans mot de passe. Saisissez le mot de passe du compte pour autoriser cette session. Orexin ne l’enregistre pas. La fin rétablit la protection immédiate.", "Nach Display-Ruhezustand oder Zuklappen können Personen in der Nähe ohne Passwort auf diesen Mac zugreifen. Das Mac-Kontopasswort autorisiert diese Sitzung. Orexin speichert es nicht. Das Arbeitsende stellt sofortigen Passwortschutz wieder her.", "Tras apagar la pantalla o cerrar la tapa, cualquier persona cercana puede acceder al Mac sin contraseña. Introduce la contraseña de tu cuenta para autorizar esta sesión. Orexin no la guarda. Al terminar se restaura la protección inmediata."],
    "临时保持未锁定仅从即时密码策略开始；结束、退出或服务恢复后重新要求即时密码。不会解锁已经锁定的 Mac。": ["暫時不鎖定僅從立即要求密碼開始；結束、退出或服務恢復後重新立即要求密碼。不會解鎖已鎖定的 Mac。", "Temporary unlocked work starts only from immediate password protection. Ending, quitting or service recovery restores that policy. It does not unlock an already locked Mac.", "一時的なロック無効は、即時のパスワード要求からのみ開始できます。終了・アプリ終了・サービス復旧で元に戻します。すでにロックされた Mac は解除しません。", "Le travail temporairement déverrouillé nécessite une protection immédiate au départ. La fin, la fermeture ou la récupération du service rétablit cette politique. Un Mac déjà verrouillé n’est pas déverrouillé.", "Temporäres entsperrtes Arbeiten setzt sofortigen Passwortschutz voraus. Ende, Beenden oder Dienstwiederherstellung stellt diese Regel wieder her. Ein bereits gesperrter Mac wird nicht entsperrt.", "El trabajo temporal desbloqueado parte de la protección inmediata. Finalizar, salir o recuperar el servicio restaura esa política. No desbloquea un Mac ya bloqueado."],
    "已取消授权，系统密码要求未更改。": ["已取消授權，系統密碼要求未更改。", "Authorization canceled. Password protection was not changed.", "許可を取り消しました。パスワード保護は変更されていません。", "Autorisation annulée. La protection n’a pas changé.", "Autorisierung abgebrochen. Passwortschutz unverändert.", "Autorización cancelada. La protección no cambió."],
    "macOS 未接受授权；请确认账户密码，或检查设备管理策略。": ["macOS 未接受授權；請確認帳號密碼，或檢查裝置管理策略。", "macOS rejected authorization. Check the account password or device management policy.", "macOS が許可を拒否しました。パスワードまたはデバイス管理ポリシーを確認してください。", "macOS a refusé l’autorisation. Vérifiez le mot de passe ou la politique de gestion.", "macOS hat die Autorisierung abgelehnt. Kontopasswort oder Geräteverwaltung prüfen.", "macOS rechazó la autorización. Comprueba la contraseña o la política de gestión."],
    "服务会话已失效，请重新开始工作。": ["服務工作階段已失效，請重新開始工作。", "The service session expired. Start work again.", "サービスのセッションが無効になりました。作業を再開してください。", "La session du service a expiré. Relancez le travail.", "Dienstsitzung abgelaufen. Arbeit erneut starten.", "La sesión del servicio caducó. Inicia el trabajo de nuevo."],
    "自动切换：": ["自動切換：", "Automatic mode: ", "自動切り替え：", "Mode automatique : ", "Automatischer Modus: ", "Modo automático: "],
    "会话条件已满足，已恢复正常模式并请求休眠与锁定。": ["工作階段條件已滿足，已恢復正常模式並要求休眠與鎖定。", "Session condition met. Normal Sleep restored; sleep and lock requested.", "終了条件を満たしました。通常モードに戻し、スリープとロックを要求しました。", "Condition atteinte. Veille normale rétablie ; veille et verrouillage demandés.", "Sitzungsbedingung erfüllt. Normaler Ruhezustand wiederhergestellt; Schlaf und Sperre angefordert.", "Condición cumplida. Reposo normal restaurado; reposo y bloqueo solicitados."],
})


reviewed_ui.update({
    "%@ · 等待系统设置": ["%@ · 等待系統設定", "%@ · System settings needed", "%@ · システム設定待ち", "%@ · Réglages système requis", "%@ · Systemeinstellungen erforderlich", "%@ · Requiere ajustes del sistema"],
    "%@ · 已核验": ["%@ · 已驗證", "%@ · Verified", "%@ · 確認済み", "%@ · Vérifié", "%@ · Bestätigt", "%@ · Verificado"],
    "等待 %@ 退出": ["等待 %@ 結束", "Waiting for %@ to quit", "%@ の終了待ち", "En attente de la fermeture de %@", "Warten auf Ende von %@", "Esperando el cierre de %@"],
    "等待 %@（PID %d）结束": ["等待 %@（PID %d）結束", "Waiting for %@ (PID %d) to exit", "%@（PID %d）の終了待ち", "En attente de %@ (PID %d)", "Warten auf %@ (PID %d)", "Esperando a %@ (PID %d)"],
    "会话进行中 · 剩余 %d 分钟": ["工作階段進行中 · 剩餘 %d 分鐘", "Session active · %d min remaining", "セッション実行中 · 残り %d 分", "Session active · %d min restantes", "Sitzung aktiv · Noch %d Min.", "Sesión activa · Quedan %d min"],
    "已观察到下载进展 · 等待文件稳定 %d 秒": ["已觀察到下載進度 · 等待檔案穩定 %d 秒", "Download progressing · Waiting %d s for file stability", "ダウンロード進行中 · 安定まで %d 秒待機", "Téléchargement en cours · Stabilité dans %d s", "Download läuft · %d s auf stabile Datei warten", "Descarga en curso · Esperando estabilidad %d s"],
    "%d 条启用 · %d 条暂停": ["%d 條啟用 · %d 條暫停", "%d enabled · %d paused", "%d 有効 · %d 停止", "%d activées · %d en pause", "%d aktiv · %d pausiert", "%d activas · %d pausadas"],
    "显示最近 %d 条 / 共 %d 条真实记录": ["顯示最近 %d 筆 / 共 %d 筆實際紀錄", "Showing latest %d / %d recorded events", "最近の %d 件を表示 / 全 %d 件", "%d derniers événements / %d enregistrés", "Letzte %d / %d aufgezeichnete Ereignisse", "Últimos %d / %d eventos registrados"],
    "当前电池 %@": ["目前電池 %@", "Current battery: %@", "現在のバッテリー：%@", "Batterie actuelle : %@", "Aktueller Akku: %@", "Batería actual: %@"],
    "尚未配置规则": ["尚未設定規則", "No Rules Configured", "ルール未設定", "Aucune règle configurée", "Keine Regeln eingerichtet", "Sin reglas configuradas"],
    "检查失败：GitHub 返回 HTTP %d。": ["檢查失敗：GitHub 回傳 HTTP %d。", "Update check failed: GitHub returned HTTP %d.", "確認できませんでした：GitHub が HTTP %d を返しました。", "Échec : GitHub a renvoyé HTTP %d.", "Prüfung fehlgeschlagen: GitHub meldet HTTP %d.", "Error: GitHub devolvió HTTP %d."],
    "发现新版本：%@": ["發現新版本：%@", "New version available: %@", "新しいバージョン：%@", "Nouvelle version : %@", "Neue Version verfügbar: %@", "Nueva versión: %@"],
    "当前已是最新公开版本（%@）。": ["目前已是最新公開版本（%@）。", "You have the latest public version (%@).", "最新の公開バージョンです（%@）。", "La dernière version publique est installée (%@).", "Die aktuelle öffentliche Version ist installiert (%@).", "Tienes la última versión pública (%@)."],
    "暂时无法连接 GitHub：%@": ["暫時無法連線 GitHub：%@", "Cannot connect to GitHub: %@", "GitHub に接続できません：%@", "Connexion à GitHub impossible : %@", "Verbindung zu GitHub nicht möglich: %@", "No se puede conectar a GitHub: %@"],
})

reviewed_ui.update({
    "仅监测所选的这次运行；同名进程重启不会延续会话。": ["僅監測選取的這次執行；同名程序重新啟動不會延續工作階段。", "Only this process instance is monitored. A restart with the same name does not continue the session.", "選択したプロセスの今回の実行のみを監視します。同名で再起動してもセッションは継続しません。", "Seule cette instance du processus est surveillée. Un redémarrage sous le même nom ne prolonge pas la session.", "Nur diese Prozessinstanz wird überwacht. Ein Neustart mit gleichem Namen setzt die Sitzung nicht fort.", "Solo se supervisa esta instancia del proceso. Reiniciarlo con el mismo nombre no continúa la sesión."],
    "会话启动失败：": ["工作階段啟動失敗：", "Session failed to start: ", "セッション開始に失敗：", "Échec du démarrage de session : ", "Sitzungsstart fehlgeschlagen: ", "No se pudo iniciar la sesión: "],
    "会话已开始：": ["工作階段已開始：", "Session started: ", "セッション開始：", "Session démarrée : ", "Sitzung gestartet: ", "Sesión iniciada: "],
    "会话已结束：": ["工作階段已結束：", "Session ended: ", "セッション終了：", "Session terminée : ", "Sitzung beendet: ", "Sesión finalizada: "],
    "会话结束：": ["工作階段結束：", "Session ended: ", "セッション終了：", "Fin de session : ", "Sitzungsende: ", "Fin de sesión: "],
    "会话状态：%@": ["工作階段狀態：%@", "Session status: %@", "セッション状態：%@", "État de session : %@", "Sitzungsstatus: %@", "Estado de sesión: %@"],
    "删除 %@": ["刪除 %@", "Delete %@", "%@ を削除", "Supprimer %@", "%@ löschen", "Eliminar %@"],
    "编辑 %@": ["編輯 %@", "Edit %@", "%@ を編集", "Modifier %@", "%@ bearbeiten", "Editar %@"],
    "即时密码保护尚未恢复；服务会继续重试。": ["即時密碼保護尚未恢復；服務將繼續重試。", "Immediate password protection has not been restored. The service will keep retrying.", "即時パスワード保護はまだ復元されていません。サービスが再試行します。", "La protection immédiate par mot de passe n’est pas rétablie. Le service réessaiera.", "Der sofortige Passwortschutz wurde noch nicht wiederhergestellt. Der Dienst versucht es erneut.", "La protección inmediata por contraseña aún no se ha restaurado. El servicio seguirá reintentándolo."],
    "将从本机日志文件中移除全部 %d 条记录；此操作无法撤销。可先导出 JSON 留存。": ["將從本機日誌中移除全部 %d 筆紀錄；無法復原。可先匯出 JSON 留存。", "Delete all %d entries from the local log. This cannot be undone. Export JSON first to keep a copy.", "ローカルログの全 %d 件を削除します。元に戻せません。必要なら先に JSON を書き出してください。", "Supprimer les %d entrées du journal local. Cette action est irréversible. Exportez d’abord le JSON pour conserver une copie.", "Alle %d Einträge im lokalen Log löschen. Dies ist nicht rückgängig zu machen. Zuerst JSON exportieren, um eine Kopie zu behalten.", "Eliminar las %d entradas del registro local. No se puede deshacer. Exporta primero el JSON para guardar una copia."],
    "工作 %d 分钟 · 合盖 %d 分钟 · %d 次启动": ["工作 %d 分鐘 · 闔蓋 %d 分鐘 · 啟動 %d 次", "Work: %d min · Lid closed: %d min · Launches: %d", "作業 %d 分 · 蓋を閉じた時間 %d 分 · 起動 %d 回", "Travail : %d min · Capot fermé : %d min · Lancements : %d", "Arbeit: %d Min. · Deckel geschlossen: %d Min. · Starts: %d", "Trabajo: %d min · Tapa cerrada: %d min · Inicios: %d"],
    "工作会话已失效，已释放本应用的保活。\n": ["工作階段已失效，已解除本應用程式的防休眠。\n", "The work session expired. This app’s sleep inhibitors were released.\n", "作業セッションが失効しました。アプリのスリープ抑止を解除しました。\n", "La session a expiré. Les blocages de veille de l’application ont été libérés.\n", "Die Arbeitssitzung ist abgelaufen. Die Schlafsperren der App wurden freigegeben.\n", "La sesión de trabajo caducó. Se liberaron los bloqueos de reposo de la aplicación.\n"],
    "工作会话已失效；恢复未完成：\n": ["工作階段已失效；恢復尚未完成：\n", "The work session expired. Recovery is incomplete:\n", "作業セッションが失効しました。復元は未完了です：\n", "La session a expiré. Restauration incomplète :\n", "Die Arbeitssitzung ist abgelaufen. Wiederherstellung unvollständig:\n", "La sesión de trabajo caducó. La restauración está incompleta:\n"],
    "已选择：%@": ["已選取：%@", "Selected: %@", "選択済み：%@", "Sélectionné : %@", "Ausgewählt: %@", "Seleccionado: %@"],
    "当前当地时间": ["目前當地時間", "Current local time", "現在の現地時刻", "Heure locale actuelle", "Aktuelle Ortszeit", "Hora local actual"],
    "当前服务不支持临时锁屏策略。": ["目前的服務不支援暫時鎖定策略。", "The installed service does not support temporary lock policy changes.", "インストール済みのサービスは一時的なロックポリシーに対応していません。", "Le service installé ne prend pas en charge les changements temporaires de verrouillage.", "Der installierte Dienst unterstützt keine vorübergehende Änderung der Sperrrichtlinie.", "El servicio instalado no admite cambios temporales de la política de bloqueo."],
    "持续 %@ 分钟": ["持續 %@ 分鐘", "For %@ min", "%@ 分間", "Pendant %@ min", "Für %@ Min.", "Durante %@ min"],
    "显示 %d / %d": ["顯示 %d / %d", "Showing %d / %d", "%d / %d 件を表示", "%d / %d affichés", "%d / %d angezeigt", "Mostrando %d / %d"],
    "暂时无法读取日志：%@": ["暫時無法讀取日誌：%@", "Cannot read the log: %@", "ログを読み取れません：%@", "Lecture du journal impossible : %@", "Log kann nicht gelesen werden: %@", "No se puede leer el registro: %@"],
    "未确认临时关闭锁定；已恢复密码保护。": ["未確認暫時關閉鎖定；已恢復密碼保護。", "Temporary unlocking was not confirmed. Password protection was restored.", "一時的なロック解除を確認できませんでした。パスワード保護を復元しました。", "La désactivation temporaire du verrouillage n’a pas été confirmée. La protection par mot de passe a été rétablie.", "Die vorübergehende Sperrdeaktivierung wurde nicht bestätigt. Der Passwortschutz wurde wiederhergestellt.", "No se confirmó la desactivación temporal del bloqueo. Se restauró la protección por contraseña."],
    "根据记录内容分类的事件：%@": ["依紀錄內容分類的事件：%@", "Event category: %@", "イベント分類：%@", "Catégorie d’événement : %@", "Ereigniskategorie: %@", "Categoría del evento: %@"],
    "根据记录内容分类的状态：%@": ["依紀錄內容分類的狀態：%@", "Recorded state: %@", "記録された状態：%@", "État enregistré : %@", "Aufgezeichneter Status: %@", "Estado registrado: %@"],
    "温度保护阈值：%@": ["溫度保護閾值：%@", "Thermal protection threshold: %@", "熱保護しきい値：%@", "Seuil de protection thermique : %@", "Wärmeschutzschwelle: %@", "Umbral de protección térmica: %@"],
    "满足条件：%@": ["符合條件：%@", "Matching rules: %@", "一致したルール：%@", "Règles correspondantes : %@", "Passende Regeln: %@", "Reglas coincidentes: %@"],
    "移除屏保例外 %@": ["移除螢幕保護程式例外 %@", "Remove screen saver exception %@", "スクリーンセーバーの例外 %@ を削除", "Retirer l’exception d’économiseur %@", "Bildschirmschoner-Ausnahme %@ entfernen", "Eliminar excepción de salvapantallas %@"],
    "移除目录 %@": ["移除目錄 %@", "Remove directory %@", "ディレクトリ %@ を削除", "Retirer le dossier %@", "Verzeichnis %@ entfernen", "Eliminar directorio %@"],
    "系统报告下载进度：%@%%": ["系統回報下載進度：%@%%", "System download progress: %@%%", "システムのダウンロード進捗：%@%%", "Progression du téléchargement système : %@%%", "Vom System gemeldeter Downloadfortschritt: %@%%", "Progreso de descarga del sistema: %@%%"],
    "系统温度压力：%@": ["系統溫度壓力：%@", "System thermal pressure: %@", "システムの熱負荷：%@", "Pression thermique système : %@", "Thermische Systembelastung: %@", "Presión térmica del sistema: %@"],
    "结束：%@": ["結束：%@", "Ends: %@", "終了：%@", "Fin : %@", "Ende: %@", "Finaliza: %@"],
    "语法检查未通过：\n%@": ["語法檢查未通過：\n%@", "Syntax check failed:\n%@", "構文チェックに失敗：\n%@", "Vérification syntaxique échouée :\n%@", "Syntaxprüfung fehlgeschlagen:\n%@", "Falló la comprobación de sintaxis:\n%@"],
    "请先解锁 Mac，再开始保持未锁定的工作模式。": ["請先解鎖 Mac，再開始保持未鎖定的工作模式。", "Unlock the Mac before starting work with locking disabled.", "ロックしない作業モードを開始する前に Mac のロックを解除してください。", "Déverrouillez le Mac avant de démarrer le travail sans verrouillage.", "Den Mac entsperren, bevor der Arbeitsmodus ohne Sperre gestartet wird.", "Desbloquea el Mac antes de iniciar el trabajo sin bloqueo."],
    "请填写%@。": ["請填寫%@。", "Enter %@.", "%@ を入力してください。", "Saisissez %@.", "%@ eingeben.", "Introduce %@."],
    "运行反馈：%@": ["執行回饋：%@", "Runtime feedback: %@", "動作フィードバック：%@", "Retour d’exécution : %@", "Laufzeitrückmeldung: %@", "Respuesta de ejecución: %@"],
    "默认": ["預設", "Default", "デフォルト", "Par défaut", "Standard", "Predeterminado"],
    "\n恢复休眠也失败：": ["\n恢復休眠也失敗：", "\nRestoring sleep also failed: ", "\nスリープの復元にも失敗：", "\nLe rétablissement de la veille a aussi échoué : ", "\nAuch das Wiederherstellen des Ruhezustands ist fehlgeschlagen: ", "\nTambién falló la restauración del reposo: "],
    "临时保持未锁定需要先将 macOS 密码要求设为「立即」。": ["暫時保持未鎖定需要先將 macOS 密碼要求設為「立即」。", "Set the macOS password requirement to Immediately before using temporary unlocked work.", "一時的にロックしない作業を使うには、macOS のパスワード要求を「すぐに」に設定してください。", "Réglez la demande de mot de passe macOS sur Immédiatement avant le travail temporairement déverrouillé.", "Die macOS-Passwortanforderung vor der vorübergehend entsperrten Arbeit auf Sofort einstellen.", "Configura la solicitud de contraseña de macOS como Inmediatamente antes del trabajo temporal sin bloqueo."],
    "临时锁屏会话已失效。": ["暫時鎖定工作階段已失效。", "The temporary lock policy lease expired.", "一時ロックポリシーのセッションが失効しました。", "La durée de la politique temporaire de verrouillage a expiré.", "Die vorübergehende Sperrrichtlinie ist abgelaufen.", "La política temporal de bloqueo caducó."],
    "另一个 Orexin 实例正在使用临时锁屏策略。": ["另一個 Orexin 執行個體正在使用暫時鎖定策略。", "Another Orexin instance is using the temporary lock policy.", "別の Orexin が一時ロックポリシーを使用しています。", "Une autre instance d’Orexin utilise la politique temporaire de verrouillage.", "Eine andere Orexin-Instanz verwendet die vorübergehende Sperrrichtlinie.", "Otra instancia de Orexin usa la política temporal de bloqueo."],
    "另一个 Orexin 实例正在使用合盖服务。": ["另一個 Orexin 執行個體正在使用闔蓋服務。", "Another Orexin instance is using the lid service.", "別の Orexin がクラムシェルサービスを使用しています。", "Une autre instance d’Orexin utilise le service capot fermé.", "Eine andere Orexin-Instanz verwendet den Deckeldienst.", "Otra instancia de Orexin usa el servicio de tapa cerrada."],
    "合盖会话已失效，请重新选择工作模式。": ["闔蓋工作階段已失效，請重新選取工作模式。", "The lid session expired. Select a work mode again.", "クラムシェルセッションが失効しました。作業モードを再選択してください。", "La session capot fermé a expiré. Sélectionnez à nouveau un mode de travail.", "Die Deckelsitzung ist abgelaufen. Einen Arbeitsmodus erneut auswählen.", "La sesión de tapa cerrada caducó. Selecciona de nuevo un modo de trabajo."],
    "合盖服务需要使用同一 Apple 开发者证书签名。当前构建仍可使用桌面工作与正常休眠。": ["闔蓋服務需要使用相同的 Apple 開發者憑證簽署。目前仍可使用桌面工作與正常休眠。", "The lid service and app must use the same Apple developer signing certificate. Desktop Work and Normal Sleep remain available.", "アプリとクラムシェルサービスは同じ Apple 開発者証明書で署名する必要があります。デスクトップ作業と通常スリープは使用できます。", "Le service et l’application doivent utiliser le même certificat de développeur Apple. Le travail sur le bureau et la veille normale restent disponibles.", "Dienst und App müssen dasselbe Apple-Entwicklerzertifikat verwenden. Desktop-Arbeit und normaler Ruhezustand bleiben verfügbar.", "El servicio y la aplicación deben usar el mismo certificado de desarrollador de Apple. El trabajo de escritorio y el reposo normal siguen disponibles."],
    "合盖防休眠未通过系统回读核验。": ["闔蓋防休眠未通過系統回讀驗證。", "System readback did not confirm lid sleep prevention.", "システムからクラムシェル時のスリープ抑止を確認できませんでした。", "Le système n’a pas confirmé le blocage de veille capot fermé.", "Das System hat die Schlafsperre bei geschlossenem Deckel nicht bestätigt.", "El sistema no confirmó el bloqueo de reposo con la tapa cerrada."],
    "命令不能为空，工作目录必须存在。": ["命令不得為空，工作目錄必須存在。", "Enter a command and an existing working directory.", "コマンドと存在する作業ディレクトリを指定してください。", "Saisissez une commande et un dossier de travail existant.", "Einen Befehl und ein vorhandenes Arbeitsverzeichnis angeben.", "Introduce un comando y un directorio de trabajo existente."],
    "恢复休眠未通过系统回读核验。": ["恢復休眠未通過系統回讀驗證。", "System readback did not confirm sleep recovery.", "システムからスリープの復元を確認できませんでした。", "Le système n’a pas confirmé le rétablissement de la veille.", "Das System hat die Wiederherstellung des Ruhezustands nicht bestätigt.", "El sistema no confirmó la restauración del reposo."],
    "恢复即时密码保护未通过系统核验。": ["恢復即時密碼保護未通過系統驗證。", "The system did not confirm restored immediate password protection.", "即時パスワード保護の復元をシステムで確認できませんでした。", "Le système n’a pas confirmé la protection immédiate par mot de passe.", "Das System hat den wiederhergestellten sofortigen Passwortschutz nicht bestätigt.", "El sistema no confirmó la protección inmediata por contraseña restaurada."],
    "操作超时：": ["操作逾時：", "Operation timed out: ", "操作がタイムアウト：", "Délai d’opération dépassé : ", "Zeitüberschreitung: ", "Tiempo de operación agotado: "],
    "无法创建任务日志。": ["無法建立工作日誌。", "Cannot create the task log.", "タスクログを作成できません。", "Impossible de créer le journal de tâche.", "Das Aufgabenlog kann nicht erstellt werden.", "No se puede crear el registro de la tarea."],
    "无法创建命令输出缓冲。": ["無法建立命令輸出緩衝區。", "Cannot create the command output buffer.", "コマンド出力バッファーを作成できません。", "Impossible de créer le tampon de sortie de commande.", "Der Ausgabepuffer für den Befehl kann nicht erstellt werden.", "No se puede crear el búfer de salida del comando."],
    "无法核验系统锁屏设置；未启用工作模式。": ["無法驗證系統鎖定設定；未啟用工作模式。", "Cannot verify system lock settings. Work mode was not enabled.", "システムのロック設定を確認できません。作業モードは有効にしていません。", "Impossible de vérifier le verrouillage système. Le mode de travail n’a pas été activé.", "Systemsperre kann nicht geprüft werden. Der Arbeitsmodus wurde nicht aktiviert.", "No se puede verificar el bloqueo del sistema. No se activó el modo de trabajo."],
    "无法读取系统防休眠状态。": ["無法讀取系統防休眠狀態。", "Cannot read the system sleep inhibition state.", "システムのスリープ抑止状態を読み取れません。", "Impossible de lire l’état du blocage de veille système.", "Der Status der Systemsperre gegen Ruhezustand kann nicht gelesen werden.", "No se puede leer el estado del bloqueo de reposo del sistema."],
    "正在切换模式，请稍候。": ["正在切換模式，請稍候。", "Switching modes. Please wait.", "モードを切り替えています。お待ちください。", "Changement de mode en cours. Patientez.", "Moduswechsel läuft. Bitte warten.", "Cambiando de modo. Espera."],
    "电源切换后的合盖保活未通过核验。": ["電源切換後的闔蓋保活未通過驗證。", "Lid sleep prevention was not confirmed after the power transition.", "電源切り替え後のクラムシェル抑止を確認できませんでした。", "Le blocage de veille capot fermé n’a pas été confirmé après le changement d’alimentation.", "Die Deckelsperre wurde nach dem Stromwechsel nicht bestätigt.", "No se confirmó el bloqueo de reposo de tapa cerrada tras el cambio de alimentación."],
    "系统回读与所选模式不一致，未标记为成功。\n": ["系統回讀與選取模式不一致，未標記為成功。\n", "System readback differs from the selected mode. Success was not confirmed.\n", "システム状態が選択モードと一致しません。成功とは確認していません。\n", "L’état système diffère du mode sélectionné. Le succès n’a pas été confirmé.\n", "Der Systemstatus entspricht nicht dem gewählten Modus. Erfolg wurde nicht bestätigt.\n", "El estado del sistema no coincide con el modo seleccionado. No se confirmó el éxito.\n"],
    "系统尚未恢复即时密码保护。": ["系統尚未恢復即時密碼保護。", "Immediate password protection has not been restored.", "即時パスワード保護はまだ復元されていません。", "La protection immédiate par mot de passe n’est pas rétablie.", "Der sofortige Passwortschutz wurde noch nicht wiederhergestellt.", "La protección inmediata por contraseña aún no se ha restaurado."],
    "系统电源状态与请求不一致。": ["系統電源狀態與要求不一致。", "System power state differs from the request.", "システムの電源状態が要求と一致しません。", "L’état d’alimentation système diffère de la demande.", "Der Systemstromstatus entspricht nicht der Anforderung.", "El estado de energía del sistema no coincide con la solicitud."],
    "系统防休眠已被关闭，请重新选择工作模式。": ["系統防休眠已關閉，請重新選取工作模式。", "System sleep inhibition was disabled. Select a work mode again.", "システムのスリープ抑止が無効になりました。作業モードを再選択してください。", "Le blocage de veille a été désactivé. Sélectionnez à nouveau un mode de travail.", "Die Systemsperre gegen Ruhezustand wurde deaktiviert. Arbeitsmodus erneut auswählen.", "Se desactivó el bloqueo de reposo del sistema. Selecciona de nuevo un modo de trabajo."],
    "系统防休眠已被其他程序开启，请先在原程序中恢复休眠。": ["其他程式已啟用系統防休眠，請先在該程式恢復休眠。", "Another app enabled system sleep inhibition. Release it in that app first.", "別のアプリがシステムのスリープを抑止しています。先にそのアプリで解除してください。", "Une autre application bloque la veille système. Libérez ce blocage dans cette application d’abord.", "Eine andere App verhindert den Systemruhezustand. Die Sperre zuerst dort freigeben.", "Otra aplicación activó el bloqueo de reposo del sistema. Libéralo primero en esa aplicación."],
    "锁屏恢复文件所有者无效。": ["鎖定恢復檔案的擁有者無效。", "The lock recovery file owner is invalid.", "ロック復元ファイルの所有者が無効です。", "Le propriétaire du fichier de récupération du verrouillage est invalide.", "Der Eigentümer der Sperrwiederherstellungsdatei ist ungültig.", "El propietario del archivo de recuperación del bloqueo no es válido."],
    "锁屏恢复用户无效。": ["鎖定恢復使用者無效。", "The lock recovery user is invalid.", "ロック復元ユーザーが無効です。", "L’utilisateur de récupération du verrouillage est invalide.", "Der Benutzer für die Sperrwiederherstellung ist ungültig.", "El usuario de recuperación del bloqueo no es válido."],
})

reviewed_ui.update({
    "正在应用并核验「%@」…": ["正在套用並驗證「%@」…", "Applying and verifying %@…", "%@ を適用して確認中…", "Application et vérification de %@…", "%@ wird angewendet und geprüft…", "Aplicando y verificando %@…"],
    "命令失败（%@），不会休眠": ["命令失敗（%@），不會休眠", "Command failed (%@). Sleep will not be requested.", "コマンド失敗（%@）。スリープは要求しません。", "Échec de commande (%@). Aucune mise en veille ne sera demandée.", "Befehl fehlgeschlagen (%@). Kein Ruhezustand wird angefordert.", "El comando falló (%@). No se solicitará el reposo."],
    "无法注册快捷键事件（%d）。": ["無法註冊快捷鍵事件（%d）。", "Cannot register the shortcut event (%d).", "ショートカットを登録できません（%d）。", "Impossible d’enregistrer le raccourci (%d).", "Tastaturereignis kann nicht registriert werden (%d).", "No se puede registrar el atajo (%d)."],
    "%@快捷键被占用或不可用（%d），请更换。": ["%@快捷鍵已被占用或無法使用（%d），請更換。", "The %@ shortcut is in use or unavailable (%d). Choose another.", "%@ のショートカットは使用中か利用不可です（%d）。別のキーを選択してください。", "Le raccourci %@ est utilisé ou indisponible (%d). Choisissez-en un autre.", "Tastenkürzel %@ ist belegt oder nicht verfügbar (%d). Ein anderes wählen.", "El atajo %@ está ocupado o no disponible (%d). Elige otro."],
    "已导出全部 %d 条运行记录。": ["已匯出全部 %d 筆執行紀錄。", "Exported all %d activity log entries.", "動作履歴を全 %d 件書き出しました。", "Les %d entrées du journal ont été exportées.", "Alle %d Aktivitätslog-Einträge exportiert.", "Se exportaron las %d entradas del registro de actividad."],
    "无法建立原生保活会话（%d）。": ["無法建立原生防休眠工作階段（%d）。", "Cannot create the native sleep inhibitor (%d).", "ネイティブのスリープ抑止を作成できません（%d）。", "Impossible de créer le blocage de veille natif (%d).", "Native Schlafsperre kann nicht erstellt werden (%d).", "No se puede crear el bloqueo de reposo nativo (%d)."],
    "无法释放原生保活会话（%d）。": ["無法解除原生防休眠工作階段（%d）。", "Cannot release the native sleep inhibitor (%d).", "ネイティブのスリープ抑止を解除できません（%d）。", "Impossible de libérer le blocage de veille natif (%d).", "Native Schlafsperre kann nicht freigegeben werden (%d).", "No se puede liberar el bloqueo de reposo nativo (%d)."],
    "已读取当前用户的 %d 个进程": ["已讀取目前使用者的 %d 個程序", "Read %d processes for the current user", "現在のユーザーの %d プロセスを取得", "%d processus lus pour l’utilisateur actuel", "%d Prozesse des aktuellen Benutzers gelesen", "Se leyeron %d procesos del usuario actual"],
    "已读取 %d 个进程；%d 个暂不可核验": ["已讀取 %d 個程序；%d 個暫時無法驗證", "Read %d processes; %d could not be verified", "%d プロセスを取得、%d 件は未確認", "%d processus lus ; %d non vérifiables", "%d Prozesse gelesen; %d nicht prüfbar", "Se leyeron %d procesos; %d no se pudieron verificar"],
    "已选择 %d 个目录": ["已選取 %d 個目錄", "%d directories selected", "%d ディレクトリを選択", "%d dossiers sélectionnés", "%d Verzeichnisse ausgewählt", "%d directorios seleccionados"],
    "低电量保护：%@%%": ["電量不足保護：%@%%", "Low battery protection: %@%%", "低バッテリー保護：%@%%", "Protection batterie faible : %@%%", "Akkuschutz: %@%%", "Protección de batería baja: %@%%"],
    "电量 %@%%，低于 %@%% 时将倒计时休眠。": ["電量 %@%%，低於 %@%% 時將倒數休眠。", "Battery: %@%%. A sleep countdown starts below %@%%.", "バッテリー %@%%。%@%% 未満でスリープのカウントダウンを開始します。", "Batterie : %@%%. Le compte à rebours de veille démarre sous %@%%.", "Akku: %@%%. Unter %@%% beginnt der Ruhezustands-Countdown.", "Batería: %@%%. La cuenta atrás de reposo comienza por debajo de %@%%."],
    "工作会话已延长 %@ 分钟。": ["工作階段已延長 %@ 分鐘。", "Work session extended by %@ min.", "作業セッションを %@ 分延長しました。", "Session de travail prolongée de %@ min.", "Arbeitssitzung um %@ Min. verlängert.", "Sesión de trabajo ampliada %@ min."],
})

reviewed_ui["未获得退出码"] = ["未取得結束代碼", "no exit code", "終了コードなし", "code de sortie indisponible", "kein Exit-Code", "sin código de salida"]

# Template cards are runtime strings, not SwiftUI literal localization keys.
reviewed_ui.update({
    "外接电源连接": ["外接電源連接", "External Power", "外部電源", "Alimentation externe", "Netzstrom", "Alimentación externa"],
    "应用 / 进程守护": ["應用程式 / 程序監控", "App / Process Monitor", "アプリ / プロセス監視", "Suivi d’app / processus", "App-/Prozessüberwachung", "Monitor de app / proceso"],
    "工作日时间表": ["工作日時間表", "Weekday Schedule", "平日のスケジュール", "Horaires en semaine", "Wochenplan", "Horario entre semana"],
    "指定 Wi-Fi 网络": ["指定 Wi-Fi 網路", "Selected Wi-Fi Network", "指定 Wi-Fi ネットワーク", "Réseau Wi-Fi choisi", "Gewähltes WLAN", "Red Wi-Fi elegida"],
    "连接外部电源时": ["連接外部電源時", "When external power is connected", "外部電源に接続したとき", "Lors du branchement au secteur", "Bei angeschlossenem Netzstrom", "Al conectar la alimentación externa"],
    "选择应用或进程后配置": ["選取應用程式或程序後設定", "Choose an app or process to configure", "アプリまたはプロセスを選択して設定", "Choisir une app ou un processus", "App oder Prozess zum Einrichten wählen", "Elige una app o un proceso"],
    "周一至周五 · 09:00–17:00，可编辑": ["週一至週五 · 09:00–17:00，可編輯", "Mon–Fri · 09:00–17:00, editable", "月〜金 · 09:00–17:00、編集可能", "Lun–ven · 09:00–17:00, modifiable", "Mo–Fr · 09:00–17:00, anpassbar", "Lun–vie · 09:00–17:00, editable"],
    "填写目标 Wi-Fi 名称后配置": ["填寫目標 Wi-Fi 名稱後設定", "Enter the Wi-Fi name to configure", "Wi-Fi 名を入力して設定", "Saisir le nom du Wi-Fi", "WLAN-Namen zum Einrichten eingeben", "Introduce el nombre de la red Wi-Fi"],
    "选择桌面工作或后台工作": ["選擇桌面工作或背景工作", "Choose Desktop or Background Work", "デスクトップまたはバックグラウンド作業を選択", "Choisir bureau ou arrière-plan", "Desktop- oder Hintergrundarbeit wählen", "Elige escritorio o segundo plano"],
    "跟随所选工作模式": ["跟隨所選工作模式", "Follow the selected work mode", "選択した作業モードに従う", "Suivre le mode de travail choisi", "Gewähltem Arbeitsmodus folgen", "Seguir el modo de trabajo elegido"],
    "条件解除后恢复正常模式": ["條件解除後恢復正常模式", "Restore Normal Sleep when no longer matched", "条件が解除されたら通常スリープに戻る", "Rétablir la veille si la condition cesse", "Ohne Treffer normalen Ruhezustand zulassen", "Restaurar el reposo si deja de cumplirse"],
    "DRAFT TEMPLATE // 未保存": ["DRAFT TEMPLATE // 未儲存", "DRAFT TEMPLATE // Unsaved", "DRAFT TEMPLATE // 未保存", "DRAFT TEMPLATE // Non enregistré", "DRAFT TEMPLATE // Ungespeichert", "DRAFT TEMPLATE // Sin guardar"],
    "OFF · 未配置": ["OFF · 未設定", "OFF · Not configured", "OFF · 未設定", "OFF · Non configuré", "OFF · Nicht eingerichtet", "OFF · Sin configurar"],
    "COND // 条件": ["COND // 條件", "COND // Condition", "COND // 条件", "COND // Condition", "COND // Bedingung", "COND // Condición"],
    "ACTION // 执行": ["ACTION // 執行", "ACTION // Action", "ACTION // 動作", "ACTION // Action", "ACTION // Aktion", "ACTION // Acción"],
    "LID // 合盖策略": ["LID // 闔蓋策略", "LID // Lid policy", "LID // 蓋の動作", "LID // Capot", "LID // Deckel", "LID // Tapa"],
    "FALLBACK // 收尾": ["FALLBACK // 收尾", "FALLBACK // On exit", "FALLBACK // 解除時", "FALLBACK // À la fin", "FALLBACK // Abschluss", "FALLBACK // Al finalizar"],
    "条件观测": ["條件觀測", "Condition Readings", "条件の観測", "Observations des conditions", "Bedingungswerte", "Lecturas de condiciones"],
    "%.0f 秒": ["%.0f 秒", "%.0f sec", "%.0f 秒", "%.0f s", "%.0f Sek.", "%.0f s"],
    "设置结束条件": ["設定結束條件", "Set End Conditions", "終了条件を設定", "Définir la fin", "Endbedingungen festlegen", "Definir condiciones de fin"],
    "工作已收尾，释放 Orexin 的保活设置，让系统恢复自然休眠。": ["工作已結束，解除 Orexin 的防休眠設定，讓系統恢復正常休眠。", "Work has ended. Orexin has released its sleep inhibitors so macOS can sleep normally.", "作業を終了しました。Orexin のスリープ抑止を解除し、macOS の通常スリープに戻します。", "Le travail est terminé. Orexin a libéré ses blocages pour permettre la veille normale de macOS.", "Die Arbeit ist beendet. Orexin hat seine Schlafsperren freigegeben; macOS kann wieder normal ruhen.", "El trabajo ha terminado. Orexin ha liberado sus bloqueos para que macOS pueda volver al reposo normal."],
    "折月": ["彎月", "Crescent", "三日月", "Croissant", "Mondsichel", "Luna creciente"],
    "会话开始与结束播放声音": ["工作階段開始與結束時播放音效", "Play a sound when sessions start and end", "セッション開始・終了時に音を鳴らす", "Son au début et à la fin des sessions", "Ton bei Sitzungsstart und -ende", "Sonido al iniciar y finalizar sesiones"],
    "延长会话时播放声音": ["延長工作階段時播放音效", "Play a sound when extending a session", "セッション延長時に音を鳴らす", "Son lors d’une prolongation de session", "Ton bei Sitzungsverlängerung", "Sonido al ampliar una sesión"],
    "立即休眠": ["立即休眠", "Sleep Now", "今すぐスリープ", "Mettre en veille", "Jetzt ruhen", "Reposo ahora"],
    "新建规则": ["新增規則", "New Rule", "ルールを追加", "Nouvelle règle", "Neue Regel", "Nueva regla"],
    "配置模板": ["設定範本", "Configure Template", "テンプレートを設定", "Configurer le modèle", "Vorlage einrichten", "Configurar plantilla"],
    "模板尚未启用": ["範本尚未啟用", "Template not enabled", "テンプレート未有効", "Modèle non activé", "Vorlage nicht aktiviert", "Plantilla no activada"],
    "机械控件音效": ["控制項音效", "Control Sounds", "操作音", "Sons des commandes", "Bedientöne", "Sonidos de controles"],
    "控件声音方案": ["控制項音效方案", "Control Sound", "操作音の種類", "Son des commandes", "Bedienton", "Sonido de control"],
    "A · 金属脆响": ["A · 金屬脆響", "A · Metallic Click", "A · 金属クリック", "A · Clic métallique", "A · Metallklick", "A · Clic metálico"],
    "B · 机械扣响": ["B · 機械扣響", "B · Mechanical Click", "B · 機械クリック", "B · Clic mécanique", "B · Mechanischer Klick", "B · Clic mecánico"],
    "C · 电子点音": ["C · 電子點音", "C · Electronic Tick", "C · 電子クリック", "C · Clic électronique", "C · Elektronischer Tick", "C · Clic electrónico"],
    "高亮、短促的金属质感": ["明亮、短促的金屬音", "A bright, brief metallic click", "明るく短い金属音", "Un clic métallique clair et bref", "Heller, kurzer Metallklick", "Un clic metálico claro y breve"],
    "较低音、干脆的机械按键": ["較低音、乾脆的機械按鍵音", "A lower, dry mechanical click", "低めの乾いた機械音", "Un clic mécanique grave et sec", "Tiefer, trockener mechanischer Klick", "Un clic mecánico grave y seco"],
    "干净、短促的电子点音": ["乾淨、短促的電子點音", "A clean, brief electronic tick", "澄んだ短い電子音", "Un clic électronique net et bref", "Klarer, kurzer elektronischer Tick", "Un clic electrónico limpio y breve"],
    "每次点击或切换只播放一声清脆短音，松开不再播放；只调整 Orexin 的控件音量。": ["每次點擊或切換只播放一聲清脆短音，放開時不播放；音量設定只影響 Orexin 控制項。", "Each click or switch plays one crisp, short sound. Releasing plays no sound. Volume affects Orexin controls only.", "クリックや切り替えで短い操作音を一度だけ鳴らします。離すときは鳴りません。音量設定は Orexin の操作音だけに適用されます。", "Chaque clic ou changement émet un seul son bref et net. Aucun son au relâchement. Le volume concerne uniquement les commandes d’Orexin.", "Jeder Klick oder Wechsel erzeugt einen kurzen, klaren Ton. Beim Loslassen ertönt nichts. Die Lautstärke gilt nur für Orexin-Bedientöne.", "Cada clic o cambio emite un único sonido breve y claro. Al soltar no suena. El volumen solo afecta a los controles de Orexin."],
    "控件音量": ["控制項音量", "Control Volume", "操作音の音量", "Volume des commandes", "Bedienton-Lautstärke", "Volumen de controles"],
    "菜单栏显示结束时间": ["選單列顯示結束時間", "Show End Time in Menu Bar", "メニューバーに終了時刻を表示", "Afficher l’heure de fin", "Endzeit in der Menüleiste anzeigen", "Mostrar hora de fin en la barra"],
    "关闭时显示剩余时长。": ["關閉時顯示剩餘時間。", "When off, show the remaining duration.", "オフの場合は残り時間を表示します。", "Sinon, afficher le temps restant.", "Ausgeschaltet wird die Restzeit angezeigt.", "Si está desactivado, mostrar el tiempo restante."],
    "使用 24 小时制": ["使用 24 小時制", "Use 24-Hour Time", "24時間表示を使用", "Format 24 heures", "24-Stunden-Format", "Usar formato de 24 horas"],
    "三套电影主题，同步切换界面色彩与月相素材。": ["三套電影主題，同步切換介面色彩與月亮圖像。", "Three film themes with matching interface colors and moon artwork.", "3つの映画テーマで、配色と月のアートワークを一緒に切り替えます。", "Trois thèmes de films aux couleurs et illustrations de lune assorties.", "Drei Filmthemen mit passenden Oberflächenfarben und Mondgrafiken.", "Tres temas de películas con colores e ilustraciones lunares a juego."],
    "深黑石墨底，青色控件与薄荷状态。": ["深黑石墨底，青色控制項與薄荷色狀態。", "Graphite black, cyan controls, mint status lights.", "黒鉛色の背景、シアンの操作部、ミントの状態表示。", "Fond graphite, commandes cyan, voyants menthe.", "Graphitschwarz, cyanfarbene Bedienelemente, mintgrüne Statusanzeigen.", "Fondo grafito, controles cian e indicadores menta."],
    "银白仪器面板，克莱因蓝交互。": ["銀白儀表面板，克萊因藍互動。", "Silver-white panels with Klein blue controls.", "銀白色のパネルとクラインブルーの操作部。", "Panneaux argentés et commandes bleu Klein.", "Silberweiße Instrumente mit Kleinblau-Bedienelementen.", "Paneles blancos plateados con controles azul Klein."],
    "深色雷达面板，琥珀色信号。": ["深色雷達面板，琥珀色訊號。", "Dark radar panels with amber signals.", "暗いレーダーパネルと琥珀色の表示。", "Panneaux radar sombres et signaux ambrés.", "Dunkle Radarpanels mit bernsteinfarbenen Signalen.", "Paneles de radar oscuros con señales ámbar."],
})

reviewed_ui.update({
    "合盖时暂停显示器保活": ["闔蓋時暫停螢幕保活", "Display wake prevention paused while lid is closed", "蓋を閉じている間は画面の常時点灯を停止", "Maintien de l’écran allumé suspendu capot fermé", "Display-Wachhaltung bei geschlossenem Deckel pausiert", "Pantalla siempre encendida suspendida con la tapa cerrada"],
    "合盖时暂停屏保延后": ["闔蓋時暫停延後螢幕保護程式", "Screen saver delay paused while lid is closed", "蓋を閉じている間はスクリーンセーバーの延期を停止", "Report de l’économiseur suspendu capot fermé", "Bildschirmschoner-Verzögerung bei geschlossenem Deckel pausiert", "Retraso del salvapantallas suspendido con la tapa cerrada"],
    "合盖时暂停鼠标移动": ["闔蓋時暫停滑鼠移動", "Cursor movement paused while lid is closed", "蓋を閉じている間はカーソル移動を停止", "Déplacement du curseur suspendu capot fermé", "Mausbewegung bei geschlossenem Deckel pausiert", "Movimiento del cursor suspendido con la tapa cerrada"],
    "合盖熄屏请求失败：": ["闔蓋熄屏要求失敗：", "Lid display sleep request failed: ", "蓋を閉じた際の画面スリープ要求に失敗：", "Échec de la mise en veille de l’écran capot fermé : ", "Display-Ruhezustand bei geschlossenem Deckel fehlgeschlagen: ", "Error al apagar la pantalla con la tapa cerrada: "],
    "合盖继续运行需要启用 Orexin 自带的系统服务，并在系统设置中批准一次。": ["闔蓋後繼續執行需要啟用 Orexin 內建的系統服務，並在系統設定中批准一次。", "To keep tasks running with the lid closed, enable Orexin’s system service and approve it once in System Settings.", "蓋を閉じても作業を続けるには、Orexin のシステムサービスを有効にし、システム設定で一度許可してください。", "Pour poursuivre les tâches capot fermé, activez le service système d’Orexin et autorisez-le une fois dans Réglages Système.", "Damit Aufgaben bei geschlossenem Deckel weiterlaufen, aktivieren Sie den Orexin-Systemdienst und erlauben ihn einmal in den Systemeinstellungen.", "Para continuar las tareas con la tapa cerrada, activa el servicio de Orexin y autorízalo una vez en Ajustes del Sistema."],
    "后台工作中": ["背景工作中", "Background Work", "バックグラウンド作業中", "Travail en arrière-plan", "Hintergrundarbeit", "Trabajo en segundo plano"],
    "桌面工作中": ["桌面工作中", "Desktop Work", "デスクトップ作業中", "Travail sur le bureau", "Desktop-Arbeit", "Trabajo en el escritorio"],
    "保持唤醒已生效": ["保持喚醒已生效", "Keep Awake Active", "スリープ防止が有効", "Maintien éveillé actif", "Wachhaltung aktiv", "Mantener despierto activo"],
    "保持唤醒已生效 · 合盖服务已授权": ["保持喚醒已生效 · 闔蓋服務已授權", "Keep Awake Active · Lid Service Authorized", "スリープ防止が有効 · クラムシェルサービス許可済み", "Maintien éveillé actif · Service capot autorisé", "Wachhaltung aktiv · Deckeldienst autorisiert", "Mantener despierto activo · Servicio de tapa autorizado"],
    "检测到合盖。": ["偵測到闔蓋。", "Lid closed.", "蓋が閉じられました。", "Capot fermé.", "Deckel geschlossen.", "Tapa cerrada."],
    "检测到开盖。": ["偵測到開蓋。", "Lid opened.", "蓋が開かれました。", "Capot ouvert.", "Deckel geöffnet.", "Tapa abierta."],
    "分钟后": ["分鐘後", "min", "分後", "min", "Min.", "min"],
    "小时后": ["小時後", "h", "時間後", "h", "Std.", "h"],
    "休眠电量阈值 // CRITICAL THRESHOLD": ["休眠電量門檻 // CRITICAL THRESHOLD", "Battery Sleep Threshold // CRITICAL THRESHOLD", "スリープのバッテリー閾値 // CRITICAL THRESHOLD", "Seuil de veille sur batterie // CRITICAL THRESHOLD", "Akku-Schwelle für Ruhezustand // CRITICAL THRESHOLD", "Umbral de batería para reposo // CRITICAL THRESHOLD"],
    "让工作按时结束，也照顾好电量。": ["讓工作準時結束，並保護電池電量。", "End work on schedule and protect the battery.", "指定時刻に作業を終了し、バッテリーを保護します。", "Terminez le travail à l’heure et protégez la batterie.", "Arbeit planmäßig beenden und den Akku schützen.", "Finaliza el trabajo a tiempo y protege la batería."],
    "合盖保活未启用": ["闔蓋保活未啟用", "Lid keep-awake is inactive", "蓋を閉じた際のスリープ防止は無効", "Maintien éveillé capot fermé inactif", "Wachhaltung bei geschlossenem Deckel inaktiv", "Mantener despierto con la tapa cerrada desactivado"],
    "合盖会话已失效；释放原生保活也失败：": ["闔蓋工作階段已失效；釋放原生保活也失敗：", "Lid session expired; releasing the sleep inhibitor also failed: ", "クラムシェルセッションが失効し、スリープ防止の解除にも失敗：", "Session capot expirée ; échec de la libération du maintien éveillé : ", "Deckelsitzung abgelaufen; Aufheben der Wachhaltung fehlgeschlagen: ", "Sesión de tapa caducada; también falló la liberación del bloqueo de reposo: "],
})

reviewed_ui["开启：合盖熄屏；关闭：保留屏幕供界面任务使用"] = ["開啟：闔蓋熄屏；關閉：保留螢幕供介面任務使用", "On: sleep displays when closed. Off: keep displays for UI tasks.", "オン：蓋を閉じると画面スリープ。オフ：画面操作のため点灯を維持。", "Actif : écran en veille capot fermé. Inactif : écran maintenu pour les tâches d’interface.", "An: Display bei geschlossenem Deckel aus. Aus: Display für UI-Aufgaben erhalten.", "Activado: apagar al cerrar. Desactivado: mantener la pantalla para tareas de interfaz."]

reviewed_ui.update({
    "工作屏幕策略": ["工作螢幕策略", "Work Display", "作業中の画面", "Écran de travail", "Arbeitsdisplay", "Pantalla de trabajo"],
    "屏幕最暗": ["螢幕最暗", "Minimum Brightness", "最低輝度", "Luminosité minimale", "Minimale Helligkeit", "Brillo mínimo"],
    "正常亮度": ["正常亮度", "Normal Brightness", "通常の輝度", "Luminosité normale", "Normale Helligkeit", "Brillo normal"],
    "立即熄屏": ["立即熄屏", "Sleep Display Now", "すぐに画面スリープ", "Éteindre l’écran maintenant", "Display sofort ausschalten", "Apagar pantalla ahora"],
    "按系统时间熄屏": ["按系統時間熄屏", "System Display Timeout", "システムの画面オフ時間", "Délai d’écran du système", "System-Displayzeit", "Tiempo de apagado del sistema"],
    "跟随系统屏幕设置": ["跟隨系統螢幕設定", "Following system display settings", "システムの画面設定に従う", "Réglages d’écran du système", "System-Displayeinstellungen", "Ajustes de pantalla del sistema"],
    "最低可见亮度 · 显示器会话保留": ["最低可見亮度 · 保留顯示器工作階段", "Lowest visible brightness · Display session kept active", "最低の可視輝度 · 画面セッションを維持", "Luminosité minimale visible · Session d’écran active", "Niedrigste sichtbare Helligkeit · Displaysitzung aktiv", "Brillo mínimo visible · Sesión de pantalla activa"],
    "正常亮度 · 显示器会话保留": ["正常亮度 · 保留顯示器工作階段", "Normal brightness · Display session kept active", "通常輝度 · 画面セッションを維持", "Luminosité normale · Session d’écran active", "Normale Helligkeit · Displaysitzung aktiv", "Brillo normal · Sesión de pantalla activa"],
    "显示器已熄灭 · 后台任务继续": ["顯示器已熄滅 · 背景任務繼續", "Display asleep · Background tasks continue", "画面スリープ中 · バックグラウンド作業は継続", "Écran en veille · Tâches en arrière-plan actives", "Display aus · Hintergrundaufgaben laufen weiter", "Pantalla apagada · Tareas en segundo plano activas"],
    "正在请求显示器立即熄灭": ["正在要求顯示器立即熄滅", "Requesting immediate display sleep", "画面スリープを要求中", "Demande de veille immédiate de l’écran", "Sofortiger Display-Ruhezustand angefordert", "Solicitando apagado inmediato de pantalla"],
    "系统设置为不自动熄屏": ["系統設定為不自動熄屏", "System display timeout is set to Never", "システムの画面オフは「しない」に設定", "L’arrêt automatique de l’écran est désactivé", "System-Displayzeit ist auf Nie gesetzt", "El apagado automático del sistema está desactivado"],
    "按系统设置闲置 %d 分钟后熄屏": ["按系統設定閒置 %d 分鐘後熄屏", "System timeout: display sleeps after %d idle min", "システム設定：無操作 %d 分で画面スリープ", "Délai système : écran en veille après %d min d’inactivité", "Systemzeit: Display aus nach %d Min. Leerlauf", "Sistema: pantalla apagada tras %d min de inactividad"],
    "屏幕策略未核验：": ["螢幕策略未驗證：", "Display policy not verified: ", "画面ポリシーを確認できません：", "Politique d’écran non vérifiée : ", "Displaystrategie nicht bestätigt: ", "Política de pantalla sin verificar: "],
    "屏幕亮度恢复失败：": ["螢幕亮度恢復失敗：", "Brightness restoration failed: ", "輝度の復元に失敗：", "Échec de restauration de luminosité : ", "Helligkeitswiederherstellung fehlgeschlagen: ", "Error al restaurar el brillo: "],
    "当前 Mac 无法读取内置屏幕亮度。": ["目前 Mac 無法讀取內建螢幕亮度。", "Cannot read this Mac’s built-in display brightness.", "この Mac の内蔵画面の輝度を取得できません。", "Impossible de lire la luminosité de l’écran intégré de ce Mac.", "Helligkeit des integrierten Displays nicht lesbar.", "No se puede leer el brillo de la pantalla integrada."],
    "当前 Mac 无法设置内置屏幕亮度。": ["目前 Mac 無法設定內建螢幕亮度。", "Cannot set this Mac’s built-in display brightness.", "この Mac の内蔵画面の輝度を設定できません。", "Impossible de régler la luminosité de l’écran intégré de ce Mac.", "Helligkeit des integrierten Displays nicht einstellbar.", "No se puede ajustar el brillo de la pantalla integrada."],
    "屏幕亮度未通过系统回读核验。": ["螢幕亮度未通過系統回讀驗證。", "System readback did not confirm the display brightness.", "システムの読み取りで画面輝度を確認できませんでした。", "La lecture système n’a pas confirmé la luminosité.", "Systemrückmeldung bestätigt die Helligkeit nicht.", "La lectura del sistema no confirmó el brillo."],
    "无法读取系统熄屏时间。": ["無法讀取系統熄屏時間。", "Cannot read the system display timeout.", "システムの画面オフ時間を取得できません。", "Impossible de lire le délai d’arrêt de l’écran.", "System-Displayzeit nicht lesbar.", "No se puede leer el tiempo de apagado del sistema."],
})

reviewed_ui["正常模式闲置时间已到，请求休眠与锁定。"] = ["正常模式的閒置時間已到，要求休眠並鎖定。", "Normal mode idle timeout reached. Sleep and lock requested.", "通常モードの無操作時間に達しました。スリープとロックを要求します。", "Délai d’inactivité du mode normal atteint. Veille et verrouillage demandés.", "Leerlaufzeit im Normalmodus erreicht. Ruhezustand und Sperre angefordert.", "Se alcanzó el tiempo de inactividad normal. Se solicita reposo y bloqueo."]

reviewed_ui.update({
    "闲置与合盖时恢复系统自然休眠，释放 Orexin 的保活设置。": ["閒置與闔蓋時恢復系統正常休眠，釋放 Orexin 的保活設定。", "Release Orexin’s sleep inhibitors so macOS can sleep normally when idle or with the lid closed.", "Orexin のスリープ防止を解除し、無操作時や蓋を閉じた際に通常のスリープを許可します。", "Libérez le maintien éveillé d’Orexin pour permettre la veille normale, au repos ou capot fermé.", "Orexins Wachhaltung aufheben, damit der Mac bei Leerlauf oder geschlossenem Deckel normal ruhen kann.", "Libera los bloqueos de reposo de Orexin para permitir el reposo normal al estar inactivo o con la tapa cerrada."],
    "系统温度压力": ["系統熱壓力", "System Thermal Pressure", "システムの熱負荷", "Pression thermique du système", "Thermische Systembelastung", "Presión térmica del sistema"],
    "系统温度压力：": ["系統熱壓力：", "System thermal pressure: ", "システムの熱負荷：", "Pression thermique du système : ", "Thermische Systembelastung: ", "Presión térmica del sistema: "],
})

reviewed_ui["Orexin · 选择器"] = ["Orexin · 選擇器", "Orexin · Selector", "Orexin · 選択", "Orexin · Sélecteur", "Orexin · Auswahl", "Orexin · Selector"]
reviewed_ui.update({
    "亮度 0% · 显示器会话保留": ["亮度 0% · 保留顯示器工作階段", "Brightness 0% · Display session active", "輝度 0% · 画面セッションを維持", "Luminosité 0% · Session d’écran active", "Helligkeit 0% · Displaysitzung aktiv", "Brillo 0% · Sesión de pantalla activa"],
    "亮度设为 0，保留屏幕会话与自动化操作": ["亮度設為 0，保留螢幕工作階段與自動化操作", "Set brightness to 0; keep the display session and GUI automation active.", "輝度を 0 に設定し、画面セッションと GUI 自動操作を維持します。", "Luminosité à 0 ; session d’écran et automatisation graphique actives.", "Helligkeit auf 0 setzen; Displaysitzung und GUI-Automatisierung bleiben aktiv.", "Brillo a 0; conserva la sesión de pantalla y la automatización gráfica."],
    "恢复原亮度，保留屏幕会话与自动化操作": ["恢復原亮度，保留螢幕工作階段與自動化操作", "Restore the original brightness; keep the display session and GUI automation active.", "元の輝度に戻し、画面セッションと GUI 自動操作を維持します。", "Luminosité d’origine ; session d’écran et automatisation graphique actives.", "Ursprüngliche Helligkeit wiederherstellen; Displaysitzung und GUI-Automatisierung bleiben aktiv.", "Restaura el brillo original; conserva la sesión y la automatización gráfica."],
    "立即关闭显示器，纯后台任务继续运行": ["立即關閉顯示器，純背景任務繼續執行", "Sleep the display now; non-GUI background tasks keep running.", "画面をすぐにオフにし、GUI を使わないバックグラウンド処理を継続します。", "Éteindre l’écran maintenant ; tâches sans interface graphique maintenues.", "Display sofort ausschalten; Hintergrundaufgaben ohne GUI laufen weiter.", "Apaga la pantalla ahora; las tareas en segundo plano sin interfaz continúan."],
    "按系统闲置时间关闭显示器，纯后台任务继续运行": ["依系統閒置時間關閉顯示器，純背景任務繼續執行", "Use the system display timeout; non-GUI background tasks keep running.", "システムの無操作時間で画面をオフにし、GUI 不要の処理を継続します。", "Délai système d’arrêt de l’écran ; tâches sans interface graphique maintenues.", "System-Displayzeit verwenden; Hintergrundaufgaben ohne GUI laufen weiter.", "Usa el tiempo de apagado del sistema; las tareas sin interfaz continúan."],
})

reviewed_ui.update({
    "只关闭显示器，唤醒后继续原屏幕策略": ["僅關閉螢幕，喚醒後繼續原螢幕策略", "Sleep the display once; resume its previous policy on wake.", "画面を一度オフにし、復帰時に元の画面設定に戻ります。", "Éteindre l’écran une fois ; reprendre sa politique précédente au réveil.", "Display einmal ausschalten; beim Aufwachen gilt wieder die vorherige Einstellung.", "Apaga la pantalla una vez; al despertar, vuelve al ajuste anterior."],
    "复制计划中的仓库地址": ["複製預計使用的儲存庫網址", "Copy Planned Repository URL", "予定のリポジトリ URL をコピー", "Copier l’URL prévue du dépôt", "Geplante Repository-URL kopieren", "Copiar URL prevista del repositorio"],
    "Orexin 仓库尚未发布版本。": ["Orexin 儲存庫尚未發佈版本。", "No releases have been published in the Orexin repository yet.", "Orexin のリポジトリにはまだリリースがありません。", "Le dépôt Orexin ne contient encore aucune version publiée.", "Im Orexin-Repository wurden noch keine Versionen veröffentlicht.", "El repositorio de Orexin aún no tiene versiones publicadas."],
    "手动检查公开发布版本。新仓库发布前，这里会明确显示尚未发布。": ["手動檢查公開發佈版本；新儲存庫尚未有版本時，會明確標示。", "Check public releases manually. If the new repository has no releases yet, that status is shown here.", "公開リリースを手動で確認します。新しいリポジトリにリリースがなければ、その状態をここに表示します。", "Vérifier manuellement les versions publiques. L’absence de version dans le nouveau dépôt est indiquée ici.", "Öffentliche Versionen manuell prüfen. Wenn das neue Repository noch keine Versionen enthält, wird dies hier angezeigt.", "Consulta manualmente las versiones públicas. Si el nuevo repositorio no tiene versiones, se indicará aquí."],
    "开源软件 · GPL-3.0-only · © 2026 Orxooo": ["開源軟體 · GPL-3.0-only · © 2026 Orxooo", "Open-source software · GPL-3.0-only · © 2026 Orxooo", "オープンソースソフトウェア · GPL-3.0-only · © 2026 Orxooo", "Logiciel libre · GPL-3.0-only · © 2026 Orxooo", "Open-Source-Software · GPL-3.0-only · © 2026 Orxooo", "Software de código abierto · GPL-3.0-only · © 2026 Orxooo"],
})

reviewed_ui.update({
    "项目与反馈": ["專案與回饋", "Project & Feedback", "プロジェクトとフィードバック", "Projet et retours", "Projekt und Feedback", "Proyecto y comentarios"],
    "版本下载": ["版本下載", "Downloads", "ダウンロード", "Téléchargements", "Downloads", "Descargas"],
    "复制仓库地址": ["複製儲存庫網址", "Copy Repository URL", "リポジトリ URL をコピー", "Copier l’URL du dépôt", "Repository-URL kopieren", "Copiar URL del repositorio"],
    "手动检查 GitHub 发布版本。Preview 版本也会检查预发布更新。": ["手動檢查 GitHub 發佈版本。Preview 版本也會檢查預發佈更新。", "Check GitHub releases manually. Preview builds also check for prerelease updates.", "GitHub のリリースを手動で確認します。Preview 版ではプレリリースも確認します。", "Vérifiez manuellement les versions GitHub. Les versions Preview recherchent aussi les préversions.", "GitHub-Veröffentlichungen manuell prüfen. Preview-Versionen berücksichtigen auch Vorabversionen.", "Consulta manualmente las versiones de GitHub. Las versiones Preview también buscan versiones preliminares."],
})

for key, values in reviewed_ui.items():
    for code, value in zip(["zh-Hant", "en", "ja", "fr", "de", "es"], values):
        translations.setdefault(code, {})[key] = value
    translations.setdefault("zh-Hans", {})[key] = key

translations["de"].update({
    "文件": "Datei", "最小化窗口": "Fenster minimieren", "缩放窗口": "Fenster vergrößern",
    "增加": "Erhöhen", "选择声音…": "Ton auswählen…",
    "控件音量 // GAIN LEVEL": "Bedienton-Lautstärke // GAIN LEVEL",
    "跟随系统选项保留在上方主题选择器中。": "Die Option für die Systemeinstellung bleibt in der Themenauswahl oben verfügbar.",
    "选择 Orexin 的界面语言。更改后立即生效。": "Wählen Sie die Sprache der Orexin-Oberfläche. Die Änderung wird sofort übernommen.",
    "配置 macOS 菜单栏图标、时间格式与留白。": "Konfigurieren Sie das macOS-Menüleistensymbol, das Zeitformat und den Abstand.",
})

for code, overrides in translations.items():
    path = ROOT / f"{code}.lproj" / "Localizable.strings"
    current = json.loads(subprocess.check_output(["plutil", "-convert", "json", "-o", "-", str(path)]))
    current.update(overrides)
    # Correct recurring machine-draft terminology throughout descriptions,
    # notifications and accessibility text, as well as the reviewed headings.
    terminology = {
        "en": [(r"\bConversation\b", "Session"), (r"\bconversation\b", "session"),
               (r"\bConversations\b", "Sessions"), (r"\bconversations\b", "sessions"),
               (r"\bhibernation\b", "sleep"), (r"\bHibernation\b", "Sleep"),
               (r"[Cc]ombined cover service", "lid service"), (r"[Ss]ealing service", "lid service"),
               (r"[Ll]ife-saving measures", "sleep inhibitors")],
        "de": [(r"Konversationen", "Sitzungen"), (r"Konversation", "Sitzung"),
               (r"Conversationsstatus", "Sitzungsstatus"), (r"Winterschlaf", "Ruhezustand"),
               (r"Zusammenkleb-Service", "Clamshell-Dienst")],
        "fr": [(r"\bConversation\b", "Session"), (r"\bconversation\b", "session"),
               (r"\bconversations\b", "sessions"), (r"\bhibernation\b", "veille")],
        "es": [(r"\bConversación\b", "Sesión"), (r"\bconversación\b", "sesión"),
               (r"\bconversaciones\b", "sesiones"), (r"\bhibernación\b", "reposo")],
        "ja": [(r"会話", "セッション"), (r"休止状態", "スリープ")],
    }
    for key, value in current.items():
        for pattern, replacement in terminology.get(code, []):
            value = re.sub(pattern, replacement, value)
        current[key] = value
    path.write_text("\n".join(f"{json.dumps(key, ensure_ascii=False)} = {json.dumps(current[key], ensure_ascii=False)};"
                              for key in sorted(current)) + "\n")
    print(code, len(current))

permission_text = {
    "zh-Hans": (
        "仅在你启用 Wi-Fi 触发规则时读取当前网络名称，不保存位置。",
        "仅用于你启用的已连接蓝牙设备触发规则。",
    ),
    "zh-Hant": (
        "僅在你啟用 Wi-Fi 觸發規則時讀取目前網路名稱，不儲存位置。",
        "僅用於你啟用的已連接藍牙裝置觸發規則。",
    ),
    "en": (
        "Reads the current Wi-Fi network name only when you enable a Wi-Fi trigger. Your location is not stored.",
        "Used only for connected Bluetooth device triggers that you enable.",
    ),
    "ja": (
        "Wi-Fi トリガーを有効にした場合にのみ、現在のネットワーク名を読み取ります。位置情報は保存しません。",
        "有効にした Bluetooth デバイスの接続トリガーにのみ使用します。",
    ),
    "fr": (
        "Lit le nom du réseau Wi-Fi actuel uniquement si vous activez un déclencheur Wi-Fi. Votre position n’est pas enregistrée.",
        "Utilisé uniquement pour les déclencheurs d’appareils Bluetooth connectés que vous activez.",
    ),
    "de": (
        "Liest den Namen des aktuellen WLANs nur bei aktiviertem WLAN-Auslöser. Dein Standort wird nicht gespeichert.",
        "Wird nur für von dir aktivierte Auslöser für verbundene Bluetooth-Geräte verwendet.",
    ),
    "es": (
        "Lee el nombre de la red Wi-Fi actual solo cuando activas un disparador Wi-Fi. No se guarda tu ubicación.",
        "Se usa solo para los activadores de dispositivos Bluetooth conectados que actives.",
    ),
}
for code, (location, bluetooth) in permission_text.items():
    values = {
        "CFBundleDisplayName": "Orexin",
        "NSLocationUsageDescription": location,
        "NSLocationWhenInUseUsageDescription": location,
        "NSBluetoothUsageDescription": bluetooth,
        "NSBluetoothAlwaysUsageDescription": bluetooth,
    }
    path = ROOT / f"{code}.lproj" / "InfoPlist.strings"
    path.write_text("\n".join(f"{json.dumps(key)} = {json.dumps(value, ensure_ascii=False)};"
                              for key, value in values.items()) + "\n")

countdown_text = {
    "zh-Hans": ("低电量：%d 秒后休眠", "任务已完成：%d 秒后休眠", "%d 分钟后恢复正常模式"),
    "zh-Hant": ("電量不足：%d 秒後休眠", "任務已完成：%d 秒後休眠", "%d 分鐘後恢復正常模式"),
    "en": ("Low battery: sleep in %d s", "Task complete: sleep in %d s", "Normal Sleep in %d min"),
    "ja": ("低バッテリー：%d 秒後にスリープ", "タスク完了：%d 秒後にスリープ", "%d 分後に通常モードへ復帰"),
    "fr": ("Batterie faible : veille dans %d s", "Tâche terminée : veille dans %d s", "Mode normal dans %d min"),
    "de": ("Akku schwach: Ruhezustand in %d Sek.", "Aufgabe fertig: Ruhezustand in %d Sek.", "Normalmodus in %d Min."),
    "es": ("Batería baja: reposo en %d s", "Tarea completada: reposo en %d s", "Modo normal en %d min"),
}
source_formats = ("低电量：%d 秒后休眠", "任务已完成：%d 秒后休眠", "%d 分钟后恢复正常模式")
for code, localized in countdown_text.items():
    path = ROOT / f"{code}.lproj" / "Localizable.strings"
    current = json.loads(subprocess.check_output(["plutil", "-convert", "json", "-o", "-", str(path)]))
    current.update(zip(source_formats, localized))
    path.write_text("\n".join(f"{json.dumps(key, ensure_ascii=False)} = {json.dumps(current[key], ensure_ascii=False)};"
                              for key in sorted(current)) + "\n")

# New timer wording is curated separately because automatic translation must not
# alter the printf placeholder used by the live menu countdown.
timer_keys = (
    " 请求休眠并锁定", "%d 分钟后休眠并锁定", "到点中断工作，恢复正常模式，并向 macOS 请求休眠与锁定。",
    "定时休眠 // TIMED SLEEP", "定时休眠：", "定时到点，恢复正常模式并请求系统休眠。",
    "已取消定时休眠。", "已设置定时休眠。",
)
timer_text = {
    "zh-Hans": timer_keys,
    "zh-Hant": (" 請求休眠並鎖定", "%d 分鐘後休眠並鎖定", "到點中斷工作、恢復正常模式，並要求 macOS 休眠和鎖定。", "定時休眠 // TIMED SLEEP", "定時休眠：", "定時已到，恢復正常模式並要求系統休眠。", "已取消定時休眠。", "已設定定時休眠。"),
    "en": (" Request Sleep and Lock", "Sleep and lock in %d min", "At the scheduled time, end work, restore normal mode, and request macOS sleep and lock.", "Scheduled Sleep // TIMED SLEEP", "Scheduled sleep: ", "Timer elapsed. Restoring normal mode and requesting system sleep.", "Scheduled sleep canceled.", "Scheduled sleep set."),
    "ja": (" スリープとロックを要求", "%d 分後にスリープしてロック", "指定時刻に作業を中断し、通常モードに戻して macOS にスリープとロックを要求します。", "指定時刻のスリープ // TIMED SLEEP", "指定時刻のスリープ：", "指定時刻になりました。通常モードに戻し、システムのスリープを要求します。", "指定時刻のスリープをキャンセルしました。", "指定時刻のスリープを設定しました。"),
    "fr": (" Demander la veille et le verrouillage", "Veille et verrouillage dans %d min", "À l’heure prévue, arrêter le travail, rétablir le mode normal et demander la veille et le verrouillage à macOS.", "Veille programmée // TIMED SLEEP", "Veille programmée : ", "Heure atteinte. Rétablissement du mode normal et demande de veille du système.", "Veille programmée annulée.", "Veille programmée définie."),
    "de": (" Ruhezustand und Sperre anfordern", "Ruhezustand und Sperre in %d Min.", "Zur festgelegten Zeit die Arbeit beenden, den Normalmodus wiederherstellen und macOS um Ruhezustand und Sperre bitten.", "Geplanter Ruhezustand // TIMED SLEEP", "Geplanter Ruhezustand: ", "Zeit erreicht. Normalmodus wird wiederhergestellt und Systemruhezustand angefordert.", "Geplanter Ruhezustand abgebrochen.", "Geplanter Ruhezustand eingestellt."),
    "es": (" Solicitar reposo y bloqueo", "Reposo y bloqueo en %d min", "A la hora prevista, detener el trabajo, restaurar el modo normal y solicitar a macOS el reposo y el bloqueo.", "Reposo programado // TIMED SLEEP", "Reposo programado: ", "Hora alcanzada. Se restaura el modo normal y se solicita el reposo del sistema.", "Reposo programado cancelado.", "Reposo programado configurado."),
}
for code, localized in timer_text.items():
    path = ROOT / f"{code}.lproj" / "Localizable.strings"
    current = json.loads(subprocess.check_output(["plutil", "-convert", "json", "-o", "-", str(path)]))
    current.update(zip(timer_keys, localized))
    path.write_text("\n".join(f"{json.dumps(key, ensure_ascii=False)} = {json.dumps(current[key], ensure_ascii=False)};"
                              for key in sorted(current)) + "\n")
