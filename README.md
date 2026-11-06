<div align="center">

<img src="App/Resources/Assets.xcassets/AppIcon.appiconset/icon-1024.png" width="120" alt="AniWorld-App-Icon">

# AniWorld für iOS

**Anime von aniworld.to als native iPhone- und iPad-App, mit eigenem Player, Downloads und ohne Account.**

[![Release](https://img.shields.io/github/v/release/Emanschi/aniworld-ios?label=Version&color=8B5CF6)](https://github.com/Emanschi/aniworld-ios/releases/latest)
[![Build](https://img.shields.io/github/actions/workflow/status/Emanschi/aniworld-ios/build.yml?branch=main&label=Build)](https://github.com/Emanschi/aniworld-ios/actions/workflows/build.yml)
![iOS 17+](https://img.shields.io/badge/iOS-17%2B-black?logo=apple)
![Swift](https://img.shields.io/badge/SwiftUI-Swift%205-F05138?logo=swift&logoColor=white)
[![Lizenz: GPL-3.0](https://img.shields.io/badge/Lizenz-GPL--3.0-blue)](LICENSE)

[**Herunterladen**](https://github.com/Emanschi/aniworld-ios/releases/latest) · [Installation](#installation) · [Funktionen](#funktionen) · [FAQ](#faq) · [Selbst bauen](#selbst-bauen)

</div>

> [!NOTE]
> Inoffizielles Fan-Projekt, nicht mit aniworld.to verbunden. Port des Python-Tools
> [dxmoc/aniworld-cli](https://github.com/dxmoc/aniworld-cli). Danke an die Autoren des Originals.

## Funktionen

| | |
|---|---|
| 🔎 **Entdecken** | Suche mit Genre-Filter, alle Animes von A–Z, Startseite mit neuen und beliebten Serien, Kalender für neue Folgen, Altersfreigabe (FSK) |
| 🎬 **Eigener Player** | Scrubber, Geschwindigkeit, Doppeltipp zum Spulen, Wischen für Helligkeit und Lautstärke, Bild-in-Bild, AirPlay, Hintergrundwiedergabe |
| ⏭️ **Intro & Outro überspringen** | Eigene Intro- und Outro-Zeiten pro Folge oder Staffel festlegen, auf Wunsch automatisch überspringen; mit Autoplay direkt zur nächsten Folge |
| 🌐 **Sprachen & Hoster** | GerDub, GerSub, EngSub; VOE und Vidmoly mit automatischem Fallback und Stream-Prüfung |
| ⬇️ **Downloads** | Folgen oder ganze Staffeln offline speichern, nur im WLAN, gesehene Folgen automatisch löschen, optional platzsparend komprimiert |
| ❤️ **Bibliothek** | Favoriten, Weiterschauen-Verlauf mit Fortschritt, Benachrichtigung bei neuen Folgen deiner Favoriten |
| ☁️ **Sync (optional)** | Favoriten, Verlauf und Fortschritt über einen Ordner in deinem iCloud Drive zwischen iPhone und iPad abgleichen |
| 📊 **Statistiken** | Watchtime, täglicher Streak mit Flammen, Top-Serien und -Genres, Sprachen, Lieblingstage und Fun Facts pro Monat, dazu ein Monatsrückblick zum Durchwischen (über iCloud synchronisiert) |
| 🔔 **Updates** | Hinweis auf neue Versionen und „Was ist neu“ nach jedem Update |

**Datenschutz:** Kein Account, keine eigenen Server, kein Tracking. Alles bleibt auf deinem Gerät
bzw. in deinem eigenen iCloud Drive. Die App spricht nur mit aniworld.to, den Hostern und für den
Update-Hinweis mit der GitHub-API.

## Installation

Die App ist nicht im App Store. Du lädst eine **IPA** herunter und installierst sie mit einem
Sideloading-Werkzeug, das sie mit deiner (kostenlosen) Apple-ID signiert.

**1. IPA herunterladen:** `AniWorld.ipa` aus dem [neuesten Release](https://github.com/Emanschi/aniworld-ios/releases/latest).

**2. Installieren**, je nach Gerät:

| Werkzeug | Läuft auf | So geht's |
|---|---|---|
| [AltStore](https://altstore.io) / [SideStore](https://sidestore.io) | iPhone (+ einmalig PC) | Quelle hinzufügen, AniWorld installieren. Updates und Signatur-Erneuerung laufen danach in der App. |
| [Impactor](https://github.com/khcrysalis/Impactor) | Linux, Windows, macOS | iPhone per USB anschließen, IPA hineinziehen, mit Apple-ID anmelden. Unter Linux muss `usbmuxd` laufen. |
| [Sideloadly](https://sideloadly.io) | Windows, macOS | IPA hineinziehen, Apple-ID eingeben, *Start*. |
| [TrollStore](https://github.com/opa334/TrollStore) | iPhone | IPA öffnen und installieren (nur auf unterstützten iOS-Versionen, keine 7-Tage-Grenze). |

AltStore/SideStore-Quelle:

```
https://github.com/Emanschi/aniworld-ios/releases/latest/download/altstore-source.json
```

**3. Auf dem iPhone freigeben:**
*Einstellungen → Allgemein → VPN & Geräteverwaltung* → deiner Apple-ID vertrauen. Ab iOS 16
zusätzlich *Einstellungen → Datenschutz & Sicherheit → Entwicklermodus* einschalten (Neustart).

**Update:** Die neue IPA einfach über die alte installieren (gleiches Werkzeug, gleiche Apple-ID).
Favoriten, Verlauf und Downloads bleiben erhalten. Die App weist dich auf neue Versionen hin.

<details>
<summary><b>iCloud-Sync einrichten (optional)</b></summary>

Beim ersten Start fragt die App nach einem Ordner. Lege im Dialog in iCloud Drive einen Ordner an
(z. B. „AniWorld“), öffne ihn und tippe auf „Öffnen“. Auf iPad und weiteren Geräten denselben Ordner
wählen. Der oberste iCloud-Drive-Ordner selbst lässt sich nicht auswählen. Die Daten liegen in einem
versteckten Unterordner und werden automatisch abgeglichen. Später änderbar unter *Einstellungen*.

</details>

## FAQ

<details>
<summary><b>Die App startet nach einer Woche nicht mehr.</b></summary>

Mit einer kostenlosen Apple-ID ist die Signatur nur 7 Tage gültig. Installiere die IPA einfach neu
(deine Daten bleiben erhalten) oder nutze AltStore/SideStore, die die Signatur automatisch erneuern.

</details>

<details>
<summary><b>„Nicht vertrauenswürdiger Entwickler“ beim Öffnen</b></summary>

*Einstellungen → Allgemein → VPN & Geräteverwaltung* → deine Apple-ID → *Vertrauen*.

</details>

<details>
<summary><b>Kann ich die IPA direkt mit der GitHub-App installieren?</b></summary>

Nein. iOS installiert nur signierte Apps, dafür brauchst du eines der Werkzeuge oben.

</details>

<details>
<summary><b>Eine Folge lädt nicht oder bricht ab.</b></summary>

Im Player über das Menü einen anderen Hoster oder eine andere Sprache wählen. Die App probiert
Hoster automatisch der Reihe nach durch; manchmal ist ein Hoster vorübergehend nicht erreichbar.

</details>

<details>
<summary><b>Wie bekomme ich „Intro überspringen“?</b></summary>

Lege Intro und Outro im Player einmal selbst fest – für eine Folge oder gleich für die ganze Staffel.
Danach erscheint der Sprung-Button automatisch (auf Wunsch wird auch automatisch übersprungen). Ohne
eigene Zeiten gibt es den festen Sprung um eine einstellbare Anzahl Sekunden.

</details>

<details>
<summary><b>Kommen Benachrichtigungen zuverlässig?</b></summary>

Die App prüft beim Öffnen und, wenn iOS es zulässt, im Hintergrund. Sideloadete Apps bekommen von
iOS nur selten Hintergrundzeit, daher kommen Benachrichtigungen teils erst beim nächsten Öffnen.

</details>

## Selbst bauen

**Ohne Mac (GitHub Actions):** Ein Push auf `main` oder ein manueller Start über *Run workflow*
baut eine unsignierte IPA (Artefakt `AniWorld-ipa`). Ein Tag `vX.Y.Z` erstellt zusätzlich ein
Release mit IPA und AltStore-Quelle. Entwickelt wird auf Feature-Branches (`name/thema`), die per
Pull Request nach `dev` gehen; `dev`, Feature-Branches und Pull Requests haben keine eigene Pipeline.

**Auf dem Mac:** Xcode und [XcodeGen](https://github.com/yonaskolb/XcodeGen).

```sh
brew install xcodegen
./scripts/build-ipa.sh                              # build/AniWorld.ipa (unsigniert)
xcodegen generate && open AniworldIOS.xcodeproj     # zum Entwickeln in Xcode
```

**Kern testen (Linux/macOS):** Die Scraping-Logik `AniworldKit` ist ein plattformunabhängiges
Swift-Package.

```sh
swift build && swift test
```

<details>
<summary><b>Projektstruktur</b></summary>

```
Package.swift            Swift-Package AniworldKit (Scraping, Extraktoren, Resolver, Skip-Zeiten)
Sources/AniworldKit/     Kernlogik, plattformunabhängig
Tests/                   Tests mit HTML-/JSON-Fixtures
App/Sources/             SwiftUI-App (Features, Player, Downloads, Sync, Benachrichtigungen, Updates)
App/Resources/           Assets, Patchnotes, Lizenztexte
project.yml              XcodeGen-Spezifikation
altstore-source.json     Vorlage der AltStore/SideStore-Quelle
scripts/                 IPA-Build, Icon, AltStore-Quelle
.github/workflows/       CI: Tests, IPA-Build, Release
```

</details>

## Mitmachen

Fehler und Ideen gerne als [Issue](https://github.com/Emanschi/aniworld-ios/issues). Pull Requests
bitte gegen `dev`. Für Beiträge mit KI-Agents gelten die Regeln in [AGENTS.md](AGENTS.md)
(u. a. Lizenzhinweise und Patchnotes bei jeder sichtbaren Änderung).

## Haftungsausschluss

Dieses Projekt hostet, speichert und verbreitet keine Inhalte. Es ruft ausschließlich öffentlich
erreichbare Seiten von aniworld.to und den dort eingebundenen Hostern auf; für die Inhalte sind deren
Betreiber verantwortlich. Keine Verbindung zu aniworld.to, den Hostern oder Apple. Beachte das in
deinem Land geltende Recht, insbesondere das Urheberrecht. Die Nutzung erfolgt auf eigene
Verantwortung.

## Lizenz

[GPL-3.0](LICENSE), wie das Original [aniworld-cli](https://github.com/dxmoc/aniworld-cli).
Verwendete Fremdsoftware (u. a. SwiftSoup):
[THIRD_PARTY_NOTICES.md](THIRD_PARTY_NOTICES.md).
