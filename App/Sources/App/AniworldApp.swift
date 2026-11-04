import SwiftUI
import AniworldKit

@main
struct AniworldApp: App {
    @State private var env = AppEnvironment.live()

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(env.library)
                .environment(env.settings)
                .environment(env.playback)
                .environment(env.sync)
                .environment(\.aniworld, env.service)
                .preferredColorScheme(.dark)
        }
    }
}

/// Wires up the shared objects. Views read them via `@Environment`.
@MainActor
struct AppEnvironment {
    let service: AniworldService
    let library: LibraryStore
    let settings: SettingsStore
    let playback: PlaybackCoordinator
    let sync: LibrarySyncService

    static func live() -> AppEnvironment {
        make(service: AniworldClient())
    }

    static func make(service: AniworldService) -> AppEnvironment {
        let library = LibraryStore()
        let settings = SettingsStore()
        return AppEnvironment(
            service: service, library: library, settings: settings,
            playback: PlaybackCoordinator(service: service, library: library, settings: settings),
            sync: LibrarySyncService(library: library)
        )
    }
}

private struct AniworldServiceKey: EnvironmentKey {
    static let defaultValue: AniworldService = AniworldClient()
}

extension EnvironmentValues {
    var aniworld: AniworldService {
        get { self[AniworldServiceKey.self] }
        set { self[AniworldServiceKey.self] = newValue }
    }
}
