import SwiftUI
import AniworldKit

/// Tab bar shell.
struct RootView: View {
    @Environment(PlaybackCoordinator.self) private var playback
    @Environment(LibrarySyncService.self) private var sync
    @Environment(EpisodeWatcher.self) private var watcher
    @Environment(LibraryStore.self) private var library
    @Environment(\.scenePhase) private var scenePhase
    @State private var updates = AppUpdateChecker.shared
    @State private var patchNotes: PatchNotesPayload?
    @State private var pendingPatchNotes: [PatchNoteEntry]?
    @State private var didCheckPatchNotes = false
    @State private var showStats = false
    @State private var pendingDeepLink: URL?

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
        // Not a fullScreenCover: while Picture in Picture plays, the player stays mounted (so the
        // AVPlayer / AVPlayerLayer survive) but is invisible and does not take touches.
        .overlay {
            if let session = playback.activeSession {
                PlayerScreen(session: session)
                    .id(session.id)
                    .opacity(playback.isMinimized ? 0 : 1)
                    .allowsHitTesting(!playback.isMinimized)
                    .accessibilityHidden(playback.isMinimized)
                    .transition(.opacity)
            }
        }
        .animation(.easeInOut(duration: 0.2), value: playback.isMinimized)
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
        .sheet(isPresented: $showStats) {
            NavigationStack {
                StatsView()
                    .toolbar {
                        ToolbarItem(placement: .topBarLeading) {
                            Button("Schließen") { showStats = false }
                        }
                    }
            }
        }
        .onOpenURL { handleWidgetURL($0) }
        .task {
            sync.start()
            if !didCheckPatchNotes {
                didCheckPatchNotes = true
                pendingPatchNotes = PatchNotesStore.consumePendingNotes()
                presentPatchNotesIfPossible()
            }
            await updates.check()
        }
        .onChange(of: sync.showOnboarding) { _, _ in processDeferred() }
        .onChange(of: playback.activeSession == nil) { _, _ in processDeferred() }
        .onChange(of: playback.isMinimized) { _, _ in processDeferred() }
        .onChange(of: patchNotes == nil) { _, _ in processDeferred() }
        .onChange(of: watcher.pendingOpenSeries == nil) { _, _ in processDeferred() }
        .onChange(of: showStats) { _, _ in processDeferred() }
        // Startet die Wiedergabe, verschwinden Serien-/Statistik-Sheet, sonst liefe der Player dahinter.
        .onChange(of: playback.activeSession?.id) { _, newID in
            if newID != nil {
                watcher.pendingOpenSeries = nil
                showStats = false
            }
        }
        .onChange(of: scenePhase) { _, newPhase in
            if newPhase == .active { Task { await updates.check() } }
        }
    }

    /// True, solange ein Sheet von RootView oder der Player (nicht minimiert) im Vordergrund ist.
    private var isBlockingPresentation: Bool {
        sync.showOnboarding || patchNotes != nil || watcher.pendingOpenSeries != nil || showStats
            || (playback.activeSession != nil && !playback.isMinimized)
    }

    /// Deep Links der Widgets: aniworld://series/<slug>, aniworld://stats, aniworld://home.
    /// Liegt gerade ein anderes Sheet oben, wird der Link gemerkt und nach dem Schließen geöffnet.
    private func handleWidgetURL(_ url: URL) {
        guard url.scheme == WidgetShared.urlScheme else { return }
        if isBlockingPresentation {
            pendingDeepLink = url
        } else {
            applyDeepLink(url)
        }
    }

    private func applyDeepLink(_ url: URL) {
        switch url.host {
        case "series":
            let slug = url.lastPathComponent
            guard slug.range(of: "^[a-z0-9][a-z0-9-]*$", options: .regularExpression) != nil else { return }
            if let series = library.history.first(where: { $0.series.slug == slug })?.series
                ?? library.favorites.first(where: { $0.series.slug == slug })?.series {
                watcher.pendingOpenSeries = series
            } else if let pageURL = URL(string: "https://aniworld.to/anime/stream/\(slug)") {
                watcher.pendingOpenSeries = SeriesSummary(slug: slug, title: slug, url: pageURL)
            }
        case "stats":
            showStats = true
        default:
            break // home: die App ist damit schon offen
        }
    }

    /// Wer zuerst da war, bleibt oben; der andere (Deep Link / Patchnotes) folgt nach dem Schließen.
    private func processDeferred() {
        if let url = pendingDeepLink, !isBlockingPresentation {
            pendingDeepLink = nil
            applyDeepLink(url)
        }
        presentPatchNotesIfPossible()
    }

    /// Shows pending patch notes only while no other sheet / cover is up.
    private func presentPatchNotesIfPossible() {
        guard let entries = pendingPatchNotes, patchNotes == nil else { return }
        guard !sync.showOnboarding, playback.activeSession == nil,
              watcher.pendingOpenSeries == nil, !showStats else { return }
        pendingPatchNotes = nil
        patchNotes = PatchNotesPayload(entries: entries)
    }
}

#Preview("App") {
    RootView().previewEnvironment()
}
