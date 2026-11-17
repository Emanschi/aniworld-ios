#!/usr/bin/env python3
"""Write the GitHub Release description for a version from App/Resources/PatchNotes.json.

Usage: release-notes.py --version 1.2.3 --repo owner/aniworld-ios [--out build/release-notes.md]

Fails if PatchNotes.json has no entry for the version, so a release can't go out without the
notes the app shows after the update.
"""
import argparse, json, os, sys

ap = argparse.ArgumentParser()
ap.add_argument("--version", required=True)
ap.add_argument("--repo", required=True, help="owner/name")
ap.add_argument("--notes", default=os.path.join(os.path.dirname(__file__), "..", "App", "Resources", "PatchNotes.json"))
ap.add_argument("--out", default="release-notes.md")
a = ap.parse_args()

entries = json.load(open(a.notes, encoding="utf-8"))
entry = next((e for e in entries if e.get("version") == a.version), None)
if entry is None or not entry.get("notes"):
    sys.exit(f"error: no patch notes for version {a.version} in {a.notes}")

source = f"https://github.com/{a.repo}/releases/latest/download/altstore-source.json"
lines = [f"## Neu in {a.version}", ""]
lines += [f"- {note}" for note in entry["notes"]]
lines += [
    "",
    "## Installieren oder aktualisieren",
    "",
    "- **AltStore / SideStore:** Quelle hinzufügen, das Update erscheint dort automatisch:",
    f"  `{source}`",
    "- **Impactor, Sideloadly & Co.:** `AniWorld.ipa` unten herunterladen und über die alte App installieren. "
    "Favoriten, Verlauf und Downloads bleiben erhalten.",
    "",
    "Die IPA ist unsigniert und wird beim Installieren mit deiner Apple-ID signiert.",
    "",
    "<details>",
    "<summary><b>Schritt für Schritt mit Impactor (Windows, macOS, Linux)</b></summary>",
    "",
    "1. **Impactor herunterladen:** auf der [Release-Seite von Impactor](https://github.com/claration/impactor/releases/latest) "
    "die Datei für dein System laden – Windows: `Impactor-windows-x86_64-setup.exe`, macOS: `Impactor-macos-universal.dmg`, "
    "Linux: `Impactor-linux-x86_64.appimage` ([Projektseite](https://github.com/claration/impactor)). "
    "Unter Linux muss zusätzlich `usbmuxd` installiert sein und laufen.",
    "2. **IPA laden:** `AniWorld.ipa` unten unter *Assets* herunterladen.",
    "3. **iPhone verbinden:** per USB-Kabel anschließen, entsperren und bei „Diesem Computer vertrauen?“ auf *Vertrauen* tippen.",
    "4. **Installieren:** Impactor öffnen, mit deiner Apple-ID anmelden (eine kostenlose reicht), "
    "`AniWorld.ipa` ins Fenster ziehen und die Installation starten.",
    "5. **Nur beim ersten Mal:** auf dem iPhone *Einstellungen → Allgemein → VPN & Geräteverwaltung* → deine Apple-ID → *Vertrauen*. "
    "Ab iOS 16 außerdem *Einstellungen → Datenschutz & Sicherheit → Entwicklermodus* einschalten (Neustart).",
    "6. **Update:** Bei einer neuen Version einfach Schritte 2–4 wiederholen; die App wird ersetzt, deine Daten bleiben.",
    "",
    "Mit einer kostenlosen Apple-ID läuft die Signatur nach **7 Tagen** ab. Dann die IPA erneut mit Impactor "
    "installieren (Daten bleiben erhalten) oder AltStore/SideStore nutzen, die automatisch erneuern.",
    "",
    "</details>",
    "",
]
with open(a.out, "w", encoding="utf-8") as f:
    f.write("\n".join(lines))
print("\n".join(lines))
