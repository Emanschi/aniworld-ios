import SwiftUI

/// Tab bar shell. Tabs are filled in by Agent B (Features/).
struct RootView: View {
    @Environment(PlaybackCoordinator.self) private var playback

    var body: some View {
        @Bindable var playback = playback
        TabView {
            Text("Start")
                .tabItem { Label("Start", systemImage: "house.fill") }
            Text("Suche")
                .tabItem { Label("Suche", systemImage: "magnifyingglass") }
            Text("Weiterschauen")
                .tabItem { Label("Weiterschauen", systemImage: "play.circle.fill") }
            Text("Favoriten")
                .tabItem { Label("Favoriten", systemImage: "heart.fill") }
            Text("Einstellungen")
                .tabItem { Label("Einstellungen", systemImage: "gearshape.fill") }
        }
        .fullScreenCover(item: $playback.activeSession) { session in
            PlayerScreen(session: session)
        }
    }
}
