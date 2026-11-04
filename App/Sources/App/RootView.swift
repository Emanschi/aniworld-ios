import SwiftUI

/// Tab bar shell.
struct RootView: View {
    @Environment(PlaybackCoordinator.self) private var playback
    @Environment(LibrarySyncService.self) private var sync

    var body: some View {
        @Bindable var playback = playback
        @Bindable var sync = sync
        TabView {
            HomeView()
                .tabItem { Label("Start", systemImage: "house.fill") }
            SearchView()
                .tabItem { Label("Suche", systemImage: "magnifyingglass") }
            HistoryView()
                .tabItem { Label("Weiterschauen", systemImage: "play.circle.fill") }
            FavoritesView()
                .tabItem { Label("Favoriten", systemImage: "heart.fill") }
            SettingsView()
                .tabItem { Label("Einstellungen", systemImage: "gearshape.fill") }
        }
        .tint(Theme.accent)
        .fullScreenCover(item: $playback.activeSession) { session in
            PlayerScreen(session: session)
        }
        .sheet(isPresented: $sync.showOnboarding, onDismiss: {
            if !sync.isConfigured { sync.skipOnboarding() }
        }) {
            SyncOnboardingView()
        }
        .task { sync.start() }
    }
}

#Preview("App") {
    RootView().previewEnvironment()
}
