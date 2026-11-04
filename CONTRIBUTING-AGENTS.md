# Build plan & ownership (for the implementing agents)

iOS port of [dxmoc/aniworld-cli](https://github.com/dxmoc/aniworld-cli) (GPL-3.0). SwiftUI, iOS 17+,
Swift 5 language mode, dark UI, **German UI texts**. No Mac is available locally: the app target is
only compiled in GitHub Actions (macOS runner, XcodeGen → unsigned IPA). `AniworldKit` builds and
tests on Linux with `swift build` / `swift test`.

## Layout

| Path | Owner | What |
|---|---|---|
| `Package.swift`, `Sources/AniworldKit/**`, `Tests/**` | A (Core) | Scraping, extractors, resolver |
| `App/Sources/Features/**`, `App/Sources/DesignSystem/**`, `App/Sources/Preview/**`, `App/Sources/App/RootView.swift` | B (UI) | All screens, design system, mock service |
| `App/Sources/Player/**`, `App/Sources/Persistence/**` | C (Player & storage) | Player, playback flow, library, settings |
| `.github/**`, `project.yml`, `App/Resources/**`, `README.md`, `LICENSE`, `altstore-source.json`, `scripts/**` | D (Build & release) | CI, IPA, AltStore source, icon, docs |

Only edit files you own. `App/Sources/App/AniworldApp.swift` belongs to the integrator.

## Contract (do not break)

- `Sources/AniworldKit/Models.swift` + `AniworldService.swift`: shared types/protocol. Adding fields
  with defaults is fine; renaming/removing is not. Need a change? Note it in your final report.
- `App/Sources/Persistence/LibraryStore.swift`, `SettingsStore.swift`, `LibraryModels.swift`:
  public API is fixed; C implements the bodies, B calls them.
- `App/Sources/Player/PlaybackCoordinator.swift`: UI starts playback only via
  `PlaybackCoordinator.play(...)` / `.resume(_:)`. RootView presents `PlayerScreen(session:)`.
- Shared objects reach views via `@Environment(LibraryStore.self)`, `@Environment(SettingsStore.self)`,
  `@Environment(PlaybackCoordinator.self)`, `@Environment(\.aniworld)`.

## Rules

- No third-party dependencies besides SwiftSoup (Core only).
- Since UI code can't be compiled locally, write conservative, well-known SwiftUI/AVKit APIs that
  exist in iOS 17 SDK; avoid iOS 18+-only APIs unless guarded with `if #available`.
- Commit your work to your branch with clear messages. Do not push.
