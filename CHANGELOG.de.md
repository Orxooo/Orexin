# Änderungsprotokoll

[简体中文](CHANGELOG.md) · [繁體中文](CHANGELOG.zh-Hant.md) · [English](CHANGELOG.en.md) · [日本語](CHANGELOG.ja.md) · [Français](CHANGELOG.fr.md) · **Deutsch** · [Español](CHANGELOG.es.md)

[Zurück zur README](README.de.md)

Installationspakete und Hinweise zum Aktualisieren findest du unter [Releases](https://github.com/Orxooo/Orexin/releases).

## V1.0.5 HotFix 1 — 2026-10-28

- Falsche Meldungen über eine fehlende Freigabe des Hilfsdienstes behoben. Maßgeblich ist jetzt die tatsächlich signaturgeprüfte Verbindung; fehlgeschlagene Verbindungen können durch erneutes Versuchen wiederhergestellt werden.
- Die Bildschirmsperre bei Inaktivität pausiert, solange der Bildschirm wach gehalten wird. Die Desktop-Anzeige und das Verhindern des Bildschirmschoners haben Vorrang; gespeicherte Regeln bleiben erhalten.
- Beschreibungen für Desktop-Modus und Autorisierung präzisiert. Versionszusatz HotFix 1 ergänzt; die Update-Prüfung behandelt Hotfixes als stabile Korrekturversionen.

## V1.0.5 — 2026-10-27

- Behoben: Nach dem Öffnen des Deckels, Aufwecken des Displays oder Entsperren während der Hintergrundarbeit fiel die Helligkeit erneut auf null. Die ursprüngliche Helligkeit wird wiederhergestellt; Aufgaben laufen weiter.
- Erneutes Schließen des Deckels oder die ausdrückliche Auswahl der minimalen Helligkeit aktiviert das Abdunkeln wieder. Gespeicherte Bildschirmvorgaben bleiben auch beim eigenständigen Hintergrunddienst erhalten.

## V1.0.4 — 2026-10-26

- Die Display-Richtlinie überschreibt Sitzungsschalter nicht mehr unbemerkt. Der Bildschirmschonerschutz lässt sich separat deaktivieren; seine Aktivierung wählt eine kompatible Display-Richtlinie.
- Die Bedienungshilfen-Berechtigung zeigt ihren Status und öffnet die Systemeinstellungen. Die Zeigerbewegung erklärt Wartezeiten und Pausen.
- Regel-Editor mit beschrifteten Feldern, einklappbaren erweiterten Optionen, festen Speichern- und Abbrechen-Aktionen sowie weniger verschachtelten Rahmen und Scrollbereichen überarbeitet.

## V1.0.3 — 2026-10-25

- „Meldungen und Hinweise“ hinzugefügt: Speichert Nachrichten zu Updates, Dienstproblemen, abgelaufenen Anforderungen, bevorstehendem Sitzungsende und Wärmeschutz.
- Pop-ups für wichtige Ereignisse und macOS-Mitteilungen hinzugefügt. Doppelte Hinweise und nachträgliche Warnungen zu bereits behobenen Problemen werden vermieden.
- Updates werden nach dem Start und anschließend alle 6 Stunden geprüft. Jede Version wird nur einmal gemeldet; Download und Installation erfolgen manuell.
- Chinesische und englische Anleitungen sowie Screenshots aktualisiert.

## V1.0.2 — 2026-10-22

- Behoben, dass sich das Hauptfenster und das Schnellzugriffsfenster nicht schließen ließen und der Menüpunkt „Schließen“ sowie `⌘W` nicht funktionierten. Nach dem Schließen eines Fensters laufen die Menüleisten-App und Hintergrundaufgaben weiter.

## V1.0.1 — 2026-10-18

- Sekündliches Flackern des Menüleistenfensters, überlagerter Text und springendes Layout während der Arbeit behoben.

## V1.0.0 — 2026-10-18

Erste stabile Veröffentlichung.

- Eigenständigen Hintergrunddienst für Aufgaben hinzugefügt. Befehle und Ausführungspläne laufen nach dem Beenden der Benutzeroberfläche weiter.
- JSON-Ausführungspläne hinzugefügt, mit Abhängigkeiten, serieller und paralleler Ausführung, Parallelitätsgrenzen, Verzweigungen für Fehlerfälle und Protokollen je Eintrag.
- Noch nicht gestartete Befehle in einem Plan lassen sich abbrechen. Bereits gestartete Befehle laufen weiter; ein Neustart des Dienstes führt Aufgaben nicht erneut aus.
- Schaltflächen, Auswahlfelder und Schalter vereinheitlicht, Layoutprobleme bei Karten, Filtern und Protokollen behoben und die Bedienung in schmalen Fenstern sowie per Tastatur verbessert.
- Behoben, dass die CLI im Installationspaket den Hintergrunddienst nicht starten konnte.

## V0.3.0 Preview.1 — 2026-10-18

Die Veröffentlichung heißt auf der Release-Seite V0.3.1 Preview; der ursprüngliche Tag lautet `v0.3.0-preview.1`, die App-Version ist `0.3.0`.

- Erweiterte Regeln mit verschachtelten Bedingungen, Prioritäten, Bedingungen, die über eine festgelegte Dauer erfüllt sein müssen, Abklingzeiten und Testläufen hinzugefügt.
- Energieanalyse hinzugefügt, um Energieanforderungen des Systems (Power Assertions), erkennbare Quellprozesse und eine Ereigniszeitleiste einzusehen.
- Arbeitsprofile sowie JSON-Import und -Export hinzugefügt. Unterschiede lassen sich vorab ansehen; Konfigurationen können zusammengeführt oder ersetzt werden. Importierte Regeln und Skripte müssen auf dem jeweiligen Mac aktiviert werden.
- CLI um Arbeitsprofile, Regeltestläufe, Energieabfragen sowie Konfigurationsimport und -export erweitert.
- Ausrichtung und Layout der Aufgabenverwaltung in schmalen Fenstern korrigiert und Kompilierungsfehler mit Xcode 26.3 behoben.

## V0.2.0 Preview — 2026-10-14

- Verwaltung paralleler Aufgaben hinzugefügt. Jede Aufgabe protokolliert ihren Exit-Code, ihre Ausgaben und ihren Status zum Wachhalten getrennt.
- Integrierte `orexin`-CLI hinzugefügt, mit Befehlsausführung, Registrierung externer Aufgaben, Heartbeats und Statusabfragen.
- Das Ende einer einzelnen Aufgabe beeinflusst andere Aufgaben nicht. Wenn alle erfolgreich abgeschlossen sind und keine andere Quelle den Mac wach hält, kann ein Countdown von 60 Sekunden bis zum Ruhezustand beginnen.
- Anforderungen zum Wachhalten lassen sich einzeln oder gemeinsam aufheben, ohne laufende Befehle zu beenden.
- Layout der Aufgabenseite überarbeitet und Texte in allen sieben Sprachen vervollständigt.

## V0.1.0 Preview — 2026-10-12

Erste öffentliche Vorschauversion.

- Arbeitsmodi für Hintergrundarbeit und Arbeit am Schreibtisch, zeit- und bedingungsgesteuerte Sitzungen sowie Steuerung der Bildschirmhelligkeit und des Ausschaltens bereitgestellt.
- Automatische Auslöser, Befehlsaufgaben, Schutz bei hoher Wärmebelastung und niedrigem Akkustand sowie einen lokalen Ausführungsverlauf unterstützt.
- Menüleistenfenster, drei Designs, sieben Sprachen und optionale Klickgeräusche bereitgestellt.
- Prüfung auf Updates für Vorschauversionen unterstützt.
- Wiederholte Ruhezustandsanforderungen nach einem zeitgesteuerten Ende und horizontale Verschiebungen beim Wechsel zwischen bestimmten Seiten behoben.
- Unter GPL-3.0-only veröffentlicht.
