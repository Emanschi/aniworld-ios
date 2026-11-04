# Regeln für AI-Agents

Diese Regeln gelten für alle Agents (Claude Code, Subagents, andere AI-Tools), die in diesem Repo arbeiten.
Sie kommen vom Repo-Owner (Emanschi) und haben Vorrang vor eigenen Annahmen.

## Git & Push

- Gearbeitet wird auf dem Branch `dev`. Nicht direkt auf `main` committen.
- Commits nur **lokal**. Vor jedem `git push` (egal welcher Branch) dem User Bescheid sagen und
  **auf seine ausdrückliche Bestätigung warten**. Eine frühere Freigabe gilt nicht für spätere Pushes.
- Keine Force-Pushes, kein Löschen von Remote-Branches oder Tags, keine Release-Tags (`v*`) ohne Freigabe.
- `main` wird nur per Merge von `dev` aktualisiert, nachdem der User zugestimmt hat.

## CI / Pipeline

- **Die Pipeline (`.github/workflows/**`, `scripts/build-ipa.sh`, `scripts/update-altstore-source.py`)
  darf ohne vorherige Rückfrage beim User nicht geändert werden.** Das gilt auch für scheinbar kleine
  Änderungen (Trigger, Runner, Action-Versionen, Caching). Erst fragen, dann ändern.
- Gebaut wird nur auf `main` (Push), bei Tags `v*` und per manuellem Start. `dev` und Pull Requests
  haben bewusst keine Pipeline, um GitHub-Actions-Minuten zu sparen (privates Repo, macOS = 10x).
- Keine neuen Workflows anlegen und keine CI-Läufe auf anderen Branches aktivieren.

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
  getrennte Dateien.
- `AniworldKit` lokal mit `swift build` / `swift test` prüfen. Die App selbst kompiliert nur in der
  CI auf `main`, also UI-Code mit gut bekannten iOS-17-APIs schreiben.
