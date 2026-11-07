# Regeln für AI-Agents

Diese Regeln gelten für alle Agents (Claude Code, Subagents, andere AI-Tools), die in diesem Repo arbeiten.
Sie kommen vom Repo-Owner (Emanschi) und haben Vorrang vor eigenen Annahmen.

## Git & Push

- Gearbeitet wird auf einem eigenen Feature-Branch, der von `dev` abzweigt, benannt nach Person und
  Thema: `emanschi/<thema>` bzw. `axsel/<thema>` (z. B. `emanschi/streak-erinnerung`). Ein Branch pro
  Aufgabe, kurzlebig halten.
- Nicht direkt auf `dev` oder `main` committen. Feature-Branches kommen per Pull Request nach `dev`;
  vor dem PR `dev` in den Branch mergen und Konflikte dort lösen.
- Fremde Feature-Branches (vom jeweils anderen) nicht ändern, rebasen oder mergen, außer der User sagt es.
- Commits nur **lokal**. Vor jedem `git push` (egal welcher Branch) dem User Bescheid sagen und
  **auf seine ausdrückliche Bestätigung warten**. Eine frühere Freigabe gilt nicht für spätere Pushes.
- Keine Force-Pushes, kein Löschen von Remote-Branches oder Tags, keine Release-Tags (`v*`) ohne Freigabe.
- Commits und Tags nur mit der GitHub-noreply-Adresse der jeweiligen Person, nie mit einer privaten
  E-Mail (`git config user.email` vor dem ersten Commit prüfen): Emanschi
  `176057845+Emanschi@users.noreply.github.com`, Axsel1 `274859569+Axsel1-eins@users.noreply.github.com`.
- `main` wird nur per Merge von `dev` aktualisiert, nachdem der User zugestimmt hat.

## CI / Pipeline

- **Die Pipeline (`.github/workflows/**`, `scripts/build-ipa.sh`, `scripts/update-altstore-source.py`)
  darf ohne vorherige Rückfrage beim User nicht geändert werden.** Das gilt auch für scheinbar kleine
  Änderungen (Trigger, Runner, Action-Versionen, Caching). Erst fragen, dann ändern.
- Gebaut wird nur auf `main` (Push), bei Tags `v*` und per manuellem Start. `dev`, Feature-Branches
  und Pull Requests haben bewusst keine Pipeline, um GitHub-Actions-Minuten zu sparen (privates Repo,
  macOS = 10x).
- Keine neuen Workflows anlegen und keine CI-Läufe auf anderen Branches aktivieren.

## Lizenzen & Pflichtangaben (immer!)

- Jede neue Abhängigkeit (Swift Package, Framework), jeder übernommene oder portierte fremde Code,
  jede Schriftart, jedes Bild/Icon oder sonstige Asset von Dritten braucht **im selben Commit**:
  1. einen Eintrag in `LicenseCatalog.items` in `App/Sources/Features/Settings/LicensesView.swift`
     (Name, Verwendung, Copyright, Lizenz, URL),
  2. den vollständigen Lizenztext in `App/Resources/Licenses/<Name>.txt`, wenn die Lizenz die
     Weitergabe des Textes verlangt (z. B. MIT, BSD, Apache-2.0 inkl. NOTICE, GPL),
  3. eine Zeile in `THIRD_PARTY_NOTICES.md`.
- Vorher prüfen, ob die Lizenz mit GPL-3.0 vereinbar ist. Bei Unklarheit oder unbekannter Lizenz:
  nicht einbauen, sondern den User fragen.
- Wird etwas entfernt oder die Version gewechselt, Einträge und Copyright-Jahre mit anpassen.
- Die GPL-Hinweise der App (Copyright, Gewährleistungsausschluss, Link zum Quellcode) und der
  Haftungsausschluss in der Lizenzen-Ansicht bleiben immer erhalten.

## Patchnotes (immer!)

- Jede für Nutzer sichtbare Änderung (neue Funktion, Bugfix, geändertes Verhalten) bekommt **im selben
  Commit** einen kurzen Eintrag auf Deutsch in `App/Resources/PatchNotes.json`, im obersten Eintrag
  (aktuelle bzw. nächste Version). Gibt es für die nächste Version noch keinen Eintrag, oben einen neuen
  anlegen.
- Kurz und verständlich für Nutzer schreiben (ein Satz pro Punkt), keine Dateinamen oder Interna.
- Rein interne Änderungen (Refactoring, Doku, Tests) brauchen keinen Eintrag.
- Die App zeigt diese Notizen nach jedem Update einmal beim ersten Start als Popup an.

## Projekt

- iOS-Port von [dxmoc/aniworld-cli](https://github.com/dxmoc/aniworld-cli), Lizenz GPL-3.0.
- Ziel: eine gut aussehende, funktionierende SwiftUI-App (keine reine CLI-Optik) mit sinnvollem
  Menü und zuverlässigem Media-Player. Favoriten, Weiterschauen-Verlauf und Fortschritt werden lokal
  gespeichert.
- App-Texte auf Deutsch.
- Verteilung als unsignierte IPA zum Sideloaden (Impactor, AltStore, SideStore, Sideloadly).
- Aufbau, Zuständigkeiten und die festen Schnittstellen zwischen Core, UI und Player stehen in
  [CONTRIBUTING-AGENTS.md](CONTRIBUTING-AGENTS.md).

## Arbeitsweise

- Größere Aufgaben werden geplant und auf Sonnet-Subagents verteilt, die bei Bedarf Haiku-Agents für
  mechanische Hilfsarbeiten nutzen. Parallel arbeitende Agents bekommen eigene Worktrees und nur
  getrennte Dateien; ihre Ergebnisse landen im Feature-Branch der Aufgabe, nicht direkt auf `dev`.
- `AniworldKit` lokal mit `swift build` / `swift test` prüfen. Die App selbst kompiliert nur in der
  CI auf `main`, also UI-Code mit gut bekannten iOS-17-APIs schreiben.
