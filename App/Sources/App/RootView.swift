import SwiftUI

/// Tab bar shell.
struct RootView: View {
    @Environment(PlaybackCoordinator.self) private var playback

    var body: some View {
        @Bindable var playback = playback
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
    }
}

#Preview("App") {
    RootView().previewEnvironment()
}
