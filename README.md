# AniWorld iOS

Nativer iOS-Client (SwiftUI, iOS 17+) zum Streamen von Anime von [aniworld.to](https://aniworld.to).
Das Projekt ist ein Port des Python-Tools [dxmoc/aniworld-cli](https://github.com/dxmoc/aniworld-cli)
(GPL-3.0) auf iPhone und iPad. Vielen Dank an die Autoren des Originals.

> Inoffizielles Fan-Projekt, nicht mit aniworld.to verbunden.

## Funktionen

- Suche nach Serien und Filmen, Startseite mit neuen und beliebten Serien
- Serien, Staffeln, Episoden und Filme
- Sprachwahl: Deutsch (GerDub), Deutsch mit Untertiteln (GerSub), Englisch mit Untertiteln (EngSub)
- Hoster VOE und Vidmoly, mit automatischem Fallback und Stream-Prüfung vor dem Abspielen
- Eigener Player im App-Design: Scrubber, Geschwindigkeit, Doppeltipp zum Spulen, Bild-in-Bild,
  AirPlay und Wiedergabe im Hintergrund
- Intro, Rückblick und Outro überspringen (Offline-Datenbank oder eigene Zeiten pro Folge/Staffel),
  auf Wunsch automatisch; mit Autoplay geht es nach dem Outro direkt zur nächsten Folge
- Downloads: einzelne Folgen oder ganze Staffeln herunterladen und offline ansehen (nur lokal)
- Weiterschauen-Verlauf und Favoriten
- Benachrichtigungen bei neuen Folgen deiner Favoriten (lokal, ohne Server)
- Optionaler Sync von Favoriten, Verlauf und Fortschritt über einen Ordner in deinem iCloud Drive
- Hinweis auf neue Versionen und „Was ist neu“ nach jedem Update
- Kein Account, keine eigenen Server: alles bleibt auf deinem Gerät bzw. in deinem iCloud Drive

## Installation

Die App ist nicht im App Store. Du installierst eine **unsignierte IPA**, die beim Installieren
mit deiner Apple-ID signiert wird.

1. Lade `AniWorld.ipa` aus dem [neuesten Release](../../releases/latest) herunter.
2. Installiere sie mit einem dieser Werkzeuge:
   - **Impactor** (Linux, Windows, macOS): iPhone per USB anschließen, IPA in Impactor ziehen,
     mit deiner Apple-ID anmelden, installieren. Unter Linux muss `usbmuxd` laufen.
   - **Sideloadly** (Windows, macOS): IPA in Sideloadly ziehen, Apple-ID eingeben, installieren.
   - **AltStore / SideStore** (mit automatischer Erneuerung): Quelle hinzufügen
     `https://github.com/Emanschi/aniworld-ios/releases/latest/download/altstore-source.json`
     und AniWorld installieren.
   - **TrollStore:** IPA öffnen und in TrollStore installieren (nur auf unterstützten iOS-Versionen).
3. Auf dem iPhone unter *Einstellungen → Allgemein → VPN & Geräteverwaltung* deiner Apple-ID
   vertrauen. Ab iOS 16 zusätzlich *Einstellungen → Datenschutz & Sicherheit → Entwicklermodus*
   aktivieren (Neustart nötig).

**Update:** Neue IPA einfach über die alte installieren (gleiches Werkzeug, gleiche Apple-ID).
Favoriten, Verlauf und Downloads bleiben erhalten.

**Wichtig:** Die GitHub-App allein kann keine IPA installieren. Mit einer kostenlosen Apple-ID läuft
die Signatur nach 7 Tagen ab und muss erneuert werden (AltStore/SideStore machen das automatisch).

**iCloud-Sync einrichten (optional):** Beim ersten Start fragt die App nach einem Ordner. Lege im
Dialog in iCloud Drive einen Ordner an (z. B. „AniWorld“), öffne ihn und tippe auf „Öffnen“. Auf
weiteren Geräten denselben Ordner wählen. Der oberste iCloud-Drive-Ordner selbst lässt sich nicht
auswählen.

## Selbst bauen

### Mit GitHub Actions (kein Mac nötig)

Ein Push auf `main` (oder ein manueller Start über *Run workflow*) baut die IPA und lädt sie als
Artefakt `AniWorld-ipa` hoch. Andere Branches (z. B. `dev`) und Pull Requests haben keine Pipeline, um Actions-Minuten zu sparen; gearbeitet wird auf `dev`, gebaut erst nach dem Merge in `main`. Ein Tag wie `v0.2.0` (`git tag v0.2.0 && git push origin v0.2.0`) erzeugt zusätzlich ein
GitHub-Release mit `AniWorld.ipa` und einer passenden `altstore-source.json`.

### Lokal auf dem Mac

Voraussetzungen: Xcode (aktuell) und [XcodeGen](https://github.com/yonaskolb/XcodeGen).

```sh
brew install xcodegen
./scripts/build-ipa.sh        # erzeugt build/AniWorld.ipa (unsigniert)
# oder zum Entwickeln in Xcode:
xcodegen generate && open AniworldIOS.xcodeproj
```

Der Kern (`AniworldKit`) lässt sich auch auf Linux/macOS testen:

```sh
swift build && swift test
```

## Projektstruktur

```
Package.swift            Swift-Package AniworldKit (Scraping, Extraktoren, Resolver)
Sources/AniworldKit/     Kernlogik, plattformunabhängig
Tests/                   Tests mit HTML-/JSON-Fixtures
App/Sources/             SwiftUI-App (Features, Design, Player, Persistenz)
App/Resources/           Assets, Skip-Datenbank, Patchnotes, Lizenztexte
project.yml              XcodeGen-Spezifikation
scripts/                 build-ipa.sh, make_icon.py, update-altstore-source.py
altstore-source.json     Vorlage der AltStore/SideStore-Quelle
.github/workflows/       CI: Tests, IPA-Build, Release
```

## Haftungsausschluss

Dieses Projekt hostet keine Inhalte. Es verlinkt und lädt ausschließlich Seiten und Streams von
aniworld.to und den dort eingebundenen Hostern. Für die Inhalte sind deren Betreiber verantwortlich.
Nutze die App verantwortungsvoll und beachte das in deinem Land geltende Recht, insbesondere das
Urheberrecht. Die Nutzung erfolgt auf eigene Verantwortung.

## Lizenz

[GPL-3.0](LICENSE), wie das Original [aniworld-cli](https://github.com/dxmoc/aniworld-cli). Hinweise zu verwendeter Fremdsoftware: [THIRD_PARTY_NOTICES.md](THIRD_PARTY_NOTICES.md).
