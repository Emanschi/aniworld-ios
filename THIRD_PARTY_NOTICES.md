# Lizenzen & Drittanbieter-Hinweise

## AniWorld für iOS

Copyright © 2026 Emanschi und Mitwirkende

Dieses Programm ist freie Software: Es darf unter den Bedingungen der GNU General Public License,
Version 3 oder (nach Wahl) jeder späteren Version, weitergegeben und/oder verändert werden.
Es wird OHNE JEDE GEWÄHRLEISTUNG bereitgestellt. Vollständiger Text: [LICENSE](LICENSE).

## Verwendete Software und übernommener Code

| Komponente | Verwendung | Copyright | Lizenz | Lizenztext in der App |
|---|---|---|---|---|
| [aniworld-cli](https://github.com/dxmoc/aniworld-cli) | Vorlage für Suche, Seiten-Parser, VOE/Vidmoly-Extraktoren, Resolver; Test-Fixtures in `Tests/AniworldKitTests/Fixtures` | © dxmoc | GPL-3.0-or-later | `App/Resources/Licenses/GPL-3.0.txt` |
| [AniSkip](https://github.com/aniskip) | Intro-/Outro-Zeitmarken: Online-Abfrage der öffentlichen API `api.aniskip.com` (abschaltbar, keine Daten mitgeliefert) | Daten: AniSkip und Community; AniSkip-Code © 2021 Lexes Jan Mantiquilla (MIT, nicht enthalten) | Daten **ohne ausdrückliche Lizenz** – nur abgefragt, nicht weitergegeben; Quellenangabe | `App/Resources/Licenses/AniSkip.txt` |
| [AniList](https://anilist.co) | Zuordnung Serientitel → MyAnimeList-ID für AniSkip (öffentliche GraphQL-API `graphql.anilist.co`) | AniList | Webdienst, kein Code oder Daten enthalten | – |
| [SwiftSoup](https://github.com/scinfu/SwiftSoup) 2.14.x | HTML-Parser (Swift Package) | © 2009–2025 Jonathan Hedley (jsoup), © 2016–2025 Nabil Chatbi | MIT | `App/Resources/Licenses/SwiftSoup-MIT.txt` |

In der App sind diese Hinweise unter **Einstellungen → Info → Lizenzen & rechtliche Hinweise**
einsehbar (`App/Sources/Features/Settings/LicensesView.swift`).

Nicht aufgeführt, weil keine Hinweispflicht besteht: Apple-Systemframeworks (SwiftUI, AVKit,
Foundation …) und SF Symbols. Das App-Icon ist selbst erstellt (`scripts/make_icon.py`).

## Haftungsausschluss

Die App hostet, speichert und verbreitet keine Inhalte. Sie ruft ausschließlich öffentlich
erreichbare Seiten von aniworld.to und der dort verlinkten Hoster auf. Keine Verbindung zu
aniworld.to, den Hostern oder Apple. Marken gehören ihren jeweiligen Inhabern.
