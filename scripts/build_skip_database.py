#!/usr/bin/env python3
"""
build_skip_database.py

Fetches intro/outro skip times from AniSkip API v2 and groups identical consecutive
episodes into clean ranges ("Folge X - Folge Y") for the local offline skip_database.json.
"""

import json
import os
import sys
import time
import urllib.request
import urllib.parse
from typing import Dict, Any, List, Optional, Tuple

USER_AGENT = "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AniworldIOS/1.0"
ANILIST_URL = "https://graphql.anilist.co"
ANISKIP_URL = "https://api.aniskip.com/v2/skip-times"

def fetch_json(url: str, post_data: Optional[bytes] = None, headers: Optional[Dict[str, str]] = None) -> Optional[Any]:
    req = urllib.request.Request(url, data=post_data)
    req.add_header("User-Agent", USER_AGENT)
    if headers:
        for k, v in headers.items():
            req.add_header(k, v)
    try:
        with urllib.request.urlopen(req, timeout=10) as resp:
            if resp.status == 200:
                return json.loads(resp.read().decode("utf-8"))
    except Exception as e:
        pass
    return None

def resolve_mal_id(title: str) -> Optional[int]:
    query = """
    query ($search: String) {
      Media(search: $search, type: ANIME) {
        idMal
      }
    }
    """
    body = json.dumps({"query": query, "variables": {"search": title}}).encode("utf-8")
    res = fetch_json(ANILIST_URL, post_data=body, headers={"Content-Type": "application/json", "Accept": "application/json"})
    if res and "data" in res and res["data"] and "Media" in res["data"] and res["data"]["Media"]:
        return res["data"]["Media"].get("idMal")
    return None

def fetch_episode_skips(mal_id: int, episode: int) -> Dict[str, Any]:
    url = f"{ANISKIP_URL}/{mal_id}/{episode}?types=op&types=ed&types=mixed-op&types=mixed-ed&types=recap&episodeLength=0"
    res = fetch_json(url, headers={"Accept": "application/json"})
    skips: Dict[str, Any] = {}
    if not res or not res.get("found") or not res.get("results"):
        return skips

    for item in res["results"]:
        skip_type = item.get("skipType")
        interval = item.get("interval", {})
        start = interval.get("startTime")
        end = interval.get("endTime")
        if start is not None and end is not None and end > start and start >= 0:
            val = {"start": round(start, 1), "end": round(end, 1)}
            if skip_type in ("op", "mixed-op"):
                if "op" not in skips:
                    skips["op"] = val
            elif skip_type in ("ed", "mixed-ed"):
                if "ed" not in skips:
                    skips["ed"] = val
            elif skip_type == "recap":
                if "recap" not in skips:
                    skips["recap"] = val
    return skips

def group_episodes(episodes_dict: Dict[int, Dict[str, Any]]) -> Dict[str, Any]:
    """Groups consecutive episodes with identical skip configs into ranges."""
    sorted_eps = sorted(episodes_dict.keys())
    if not sorted_eps:
        return {}

    grouped: Dict[str, Any] = {}
    i = 0
    while i < len(sorted_eps):
        start_ep = sorted_eps[i]
        end_ep = start_ep
        val = episodes_dict[start_ep]

        while i + 1 < len(sorted_eps) and sorted_eps[i + 1] == end_ep + 1 and episodes_dict[sorted_eps[i + 1]] == val:
            end_ep = sorted_eps[i + 1]
            i += 1

        range_key = f"{start_ep}-{end_ep}" if start_ep != end_ep else str(start_ep)
        grouped[range_key] = val
        i += 1

    return grouped

def build_series_seasons(slug: str, season_configs: List[Tuple[str, int, int]]) -> Dict[str, Any]:
    """
    season_configs: [(search_title, season_number, episode_count), ...]
    """
    series_data: Dict[str, Any] = {}
    for title, season_num, ep_count in season_configs:
        print(f"Fetching MAL ID for '{title}' (Season {season_num}, {ep_count} episodes)...")
        mal_id = resolve_mal_id(title)
        if not mal_id:
            print(f"  [!] Could not resolve MAL ID for {title}")
            continue

        print(f"  [+] Found MAL ID {mal_id}. Fetching episodes 1..{ep_count}...")
        ep_skips: Dict[int, Dict[str, Any]] = {}
        for ep in range(1, ep_count + 1):
            skips = fetch_episode_skips(mal_id, ep)
            ep_skips[ep] = skips
            time.sleep(0.08) # Courtesy rate limit

        grouped = group_episodes(ep_skips)
        series_data[str(season_num)] = grouped
        print(f"  [+] Season {season_num} grouped into {len(grouped)} intervals/ranges.")

    return series_data

def main():
    db_path = "/root/aniworld-ios/App/Resources/skip_database.json"
    existing: Dict[str, Any] = {}
    if os.path.exists(db_path):
        try:
            with open(db_path, "r", encoding="utf-8") as f:
                existing = json.load(f)
        except Exception:
            existing = {}

    # Definitions of top popular anime series: (slug, [(search_title, season_num, max_episodes), ...])
    popular_anime = [
        (
            "attack-on-titan",
            [
                ("Attack on Titan", 1, 25),
                ("Attack on Titan Season 2", 2, 12),
                ("Attack on Titan Season 3", 3, 22),
                ("Attack on Titan The Final Season", 4, 28),
            ]
        ),
        (
            "jujutsu-kaisen",
            [
                ("Jujutsu Kaisen", 1, 24),
                ("Jujutsu Kaisen 2nd Season", 2, 23),
            ]
        ),
        (
            "demon-slayer-kimetsu-no-yaiba",
            [
                ("Demon Slayer: Kimetsu no Yaiba", 1, 26),
                ("Demon Slayer: Kimetsu no Yaiba Entertainment District Arc", 2, 11),
                ("Demon Slayer: Kimetsu no Yaiba Swordsmith Village Arc", 3, 11),
                ("Demon Slayer: Kimetsu no Yaiba Hashira Training Arc", 4, 8),
            ]
        ),
        (
            "death-note",
            [
                ("Death Note", 1, 37),
            ]
        ),
        (
            "chainsaw-man",
            [
                ("Chainsaw Man", 1, 12),
            ]
        ),
        (
            "solo-leveling",
            [
                ("Solo Leveling", 1, 12),
            ]
        ),
        (
            "frieren-beyond-journeys-end",
            [
                ("Sousou no Frieren", 1, 28),
            ]
        ),
        (
            "spy-x-family",
            [
                ("Spy x Family", 1, 25),
                ("Spy x Family Season 2", 2, 12),
            ]
        )
    ]

    for slug, seasons in popular_anime:
        print(f"\n=== Processing Anime: {slug} ===")
        series_data = build_series_seasons(slug, seasons)
        if series_data:
            existing[slug] = series_data

    os.makedirs(os.path.dirname(db_path), exist_ok=True)
    with open(db_path, "w", encoding="utf-8") as f:
        json.dump(existing, f, indent=2, ensure_ascii=False)

    print(f"\n[DONE] Successfully saved skip database to {db_path} with {len(existing)} series!")

if __name__ == "__main__":
    main()
