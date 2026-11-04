import SwiftUI

/// Tab bar shell.
struct RootView: View {
    @Environment(PlaybackCoordinator.self) private var playback
    @Environment(LibrarySyncService.self) private var sync
    @Environment(EpisodeWatcher.self) private var watcher
    @Environment(\.scenePhase) private var scenePhase
    @State private var updates = AppUpdateChecker.shared
    @State private var patchNotes: PatchNotesPayload?
    @State private var pendingPatchNotes: [PatchNoteEntry]?
    @State private var didCheckPatchNotes = false

    var body: some View {
        @Bindable var playback = playback
        @Bindable var sync = sync
        @Bindable var watcher = watcher
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
        .overlay(alignment: .top) {
            if updates.shouldShowBanner, let update = updates.availableUpdate {
                UpdateBannerView(update: update) {
                    withAnimation(.easeInOut(duration: 0.25)) { updates.dismissBanner() }
                }
                .padding(.top, 6)
                .transition(.move(edge: .top).combined(with: .opacity))
            }
        }
        .animation(.easeInOut(duration: 0.25), value: updates.shouldShowBanner)
        .sheet(item: $patchNotes) { (payload: PatchNotesPayload) in
            PatchNotesSheet(entries: payload.entries)
        }
        .sheet(item: $watcher.pendingOpenSeries) { (series: SeriesSummary) in
            NavigationStack {
                SeriesDetailView(series: series)
                    .toolbar {
                        ToolbarItem(placement: .topBarLeading) {
                            Button("Schließen") { watcher.pendingOpenSeries = nil }
                        }
                    }
            }
        }
        .task {
            sync.start()
            if !didCheckPatchNotes {
                didCheckPatchNotes = true
                pendingPatchNotes = PatchNotesStore.consumePendingNotes()
                presentPatchNotesIfPossible()
            }
            await updates.check()
        }
        .onChange(of: sync.showOnboarding) { _, _ in presentPatchNotesIfPossible() }
        .onChange(of: playback.activeSession == nil) { _, _ in presentPatchNotesIfPossible() }
        .onChange(of: scenePhase) { _, newPhase in
            if newPhase == .active { Task { await updates.check() } }
        }
    }

    /// Shows pending patch notes only while no other sheet / cover is up.
    private func presentPatchNotesIfPossible() {
        guard let entries = pendingPatchNotes, patchNotes == nil else { return }
        guard !sync.showOnboarding, playback.activeSession == nil else { return }
        pendingPatchNotes = nil
        patchNotes = PatchNotesPayload(entries: entries)
    }
}

#Preview("App") {
    RootView().previewEnvironment()
}
