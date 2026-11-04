# AniWorld iOS

Nativer iOS-Client (SwiftUI, iOS 17+) zum Streamen von Anime von [aniworld.to](https://aniworld.to).
Das Projekt ist ein Port des Python-Tools [dxmoc/aniworld-cli](https://github.com/dxmoc/aniworld-cli)
(GPL-3.0) auf iPhone und iPad. Vielen Dank an die Autoren des Originals.

> Inoffizielles Fan-Projekt, nicht mit aniworld.to verbunden.

## Funktionen

- Suche nach Serien und Filmen
- Serien, Staffeln, Episoden und Filme
- Sprachwahl: Deutsch (GerDub), Deutsch mit Untertiteln (GerSub), Englisch mit Untertiteln (EngSub)
- Hoster VOE und Vidmoly, mit automatischem Fallback und Stream-Prüfung vor dem Abspielen
- Nativer Player mit Bild-in-Bild, AirPlay und Wiedergabe im Hintergrund
- Intro und Outro überspringen (automatische Erkennung mit genauen Zeitmarken oder manueller Sprung)
- Autoplay der nächsten Folge
- Weiterschauen-Verlauf
- Favoriten
- Alles wird lokal auf dem Gerät gespeichert, es gibt keinen Account und keine eigenen Server

## Installation

Die App ist nicht im App Store. Du installierst eine **unsignierte IPA**, die beim Installieren
mit deiner Apple-ID (oder via TrollStore) signiert wird.

1. Lade `AniWorld.ipa` aus den [Releases](../../releases/latest) herunter
   (oder aus den Artefakten eines Workflow-Laufs im Reiter *Actions*).
2. Installiere sie mit einer dieser Möglichkeiten:
   - **AltStore / SideStore (empfohlen, mit automatischen Updates):** Quelle hinzufügen
     `https://github.com/Emanschi/aniworld-ios/releases/latest/download/altstore-source.json`
     und AniWorld installieren. Die Quelle wird bei jedem Release automatisch aktualisiert.
   - **Sideloadly:** IPA in Sideloadly ziehen, Apple-ID eingeben, installieren.
   - **TrollStore:** IPA öffnen und in TrollStore installieren (nur auf unterstützten iOS-Versionen).

**Wichtig:** Die GitHub-App allein kann keine IPA installieren. iOS erlaubt nur signierte Apps;
dafür brauchst du eines der oben genannten Werkzeuge. Mit einer kostenlosen Apple-ID läuft die
Signatur 7 Tage, AltStore/SideStore erneuern sie automatisch.

**Hinweis:** Solange das Repository privat ist, funktionieren die AltStore-Quelle, die
`raw.githubusercontent.com`-Icon-URLs und die Release-Download-Links ohne Anmeldung nicht. Sie
funktionieren erst, wenn das Repository öffentlich ist. Im Release-Workflow wird die
`altstore-source.json` automatisch passend zum Repository erzeugt.

## Selbst bauen

### Mit GitHub Actions (kein Mac nötig)

Ein Push auf `main` (oder ein manueller Start über *Run workflow*) baut die IPA und lädt sie als
Artefakt `AniWorld-ipa` hoch. Andere Branches (z. B. `dev`) und Pull Requests haben keine Pipeline, um Actions-Minuten zu sparen; gearbeitet wird auf `dev`, gebaut erst nach dem Merge in `main`. Ein Tag wie `v0.1.0` (`git tag v0.1.0 && git push origin v0.1.0`) erzeugt zusätzlich ein
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
App/Resources/           Assets (App-Icon, Akzentfarbe)
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
