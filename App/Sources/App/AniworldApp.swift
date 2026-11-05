import SwiftUI
import AniworldKit

@main
struct AniworldApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @State private var env: AppEnvironment
    @Environment(\.scenePhase) private var scenePhase

    @MainActor
    init() {
        let env = AppEnvironment.live()
        _env = State(initialValue: env)
        // Muss vor dem Ende des App-Starts passieren (BGTaskScheduler.register).
        env.watcher.configure()
    }

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(env.library)
                .environment(env.settings)
                .environment(env.playback)
                .environment(env.sync)
                .environment(env.downloads)
                .environment(env.watcher)
                .environment(env.stats)
                .environment(\.aniworld, env.service)
                .preferredColorScheme(.dark)
                .onChange(of: scenePhase) { _, newPhase in
                    switch newPhase {
                    case .active:
                        Task { await env.watcher.runIfDue() }
                    case .background:
                        env.watcher.scheduleBackgroundRefresh()
                    default:
                        break
                    }
                }
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
    let downloads: DownloadManager
    let watcher: EpisodeWatcher
    let stats: WatchStatsStore

    static func live() -> AppEnvironment {
        make(service: AniworldClient())
    }

    static func make(service: AniworldService, stats: WatchStatsStore? = nil) -> AppEnvironment {
        let stats: WatchStatsStore = stats ?? WatchStatsStore()
        let library = LibraryStore()
        let settings = SettingsStore()
        return AppEnvironment(
            service: service, library: library, settings: settings,
            playback: PlaybackCoordinator(service: service, library: library, settings: settings),
            sync: LibrarySyncService(library: library, stats: stats),
            downloads: DownloadManager(service: service, settings: settings, library: library),
            watcher: EpisodeWatcher(service: service, library: library, settings: settings),
            stats: stats
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
