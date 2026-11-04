#!/usr/bin/env python3
"""Fill altstore-source.json for a release.

Usage: update-altstore-source.py --ipa AniWorld.ipa --version 1.2.3 --repo owner/aniworld-ios \
           [--template altstore-source.json] [--out build/altstore-source.json]

Replaces GITHUB_OWNER with the repo owner, and sets version/date/size/downloadURL of the newest
version entry. The result is attached to the GitHub Release as `altstore-source.json`, so the
stable source URL is
  https://github.com/<owner>/aniworld-ios/releases/latest/download/altstore-source.json
"""
import argparse, datetime, json, os

ap = argparse.ArgumentParser()
ap.add_argument("--ipa", required=True)
ap.add_argument("--version", required=True)
ap.add_argument("--repo", required=True, help="owner/name")
ap.add_argument("--tag", help="release tag (default: v<version>)")
ap.add_argument("--template", default=os.path.join(os.path.dirname(__file__), "..", "altstore-source.json"))
ap.add_argument("--out", default="altstore-source.json")
a = ap.parse_args()

owner, name = a.repo.split("/", 1)
tag = a.tag or f"v{a.version}"
raw = open(a.template, encoding="utf-8").read().replace("GITHUB_OWNER", owner).replace("aniworld-ios", name)
data = json.loads(raw)

ipa_url = f"https://github.com/{a.repo}/releases/download/{tag}/AniWorld.ipa"
date = datetime.datetime.now(datetime.timezone.utc).strftime("%Y-%m-%d")
size = os.path.getsize(a.ipa)
data["sourceURL"] = f"https://github.com/{a.repo}/releases/latest/download/altstore-source.json"
for app in data["apps"]:
    v = app["versions"][0]
    v.update(version=a.version, date=date, size=size, downloadURL=ipa_url)
    # legacy (AltStore < 1.5) top-level fields
    app.update(version=a.version, versionDate=date, size=size, downloadURL=ipa_url)

os.makedirs(os.path.dirname(os.path.abspath(a.out)), exist_ok=True)
with open(a.out, "w", encoding="utf-8") as f:
    json.dump(data, f, indent=2, ensure_ascii=False)
    f.write("\n")
print(f"wrote {a.out}: version {a.version}, {size} bytes, {ipa_url}")
