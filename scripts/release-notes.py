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
]
with open(a.out, "w", encoding="utf-8") as f:
    f.write("\n".join(lines))
print("\n".join(lines))
