import SwiftUI
import AVFoundation
import UIKit
import AniworldKit

/// Full-screen player with our own Netflix-style controls. The video is rendered by
/// `PlayerSurfaceView`; all controls live in `Player/Controls`.
struct PlayerScreen: View {
    let session: PlaybackSession

    @Environment(PlaybackCoordinator.self) private var playback
    @Environment(LibraryStore.self) private var library
    @Environment(SettingsStore.self) private var settings
    @Environment(\.aniworld) private var service
    @Environment(\.scenePhase) private var scenePhase

    @State private var viewModel: PlayerViewModel?

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            if let viewModel {
                PlayerContentView(vm: viewModel)
            }
        }
        .statusBarHidden(true)
        .persistentSystemOverlays(.hidden)
        .task {
            guard viewModel == nil else { return }
            let vm = PlayerViewModel(session: session)
            vm.attach(service: service, library: library, settings: settings, coordinator: playback)
            viewModel = vm
            vm.start()
        }
        .onAppear { PlayerOrientation.enterPlayer() }
        .onDisappear {
            viewModel?.shutdown()
            PlayerOrientation.leavePlayer()
        }
        .onChange(of: scenePhase) { _, phase in
            if phase != .active {
                viewModel?.saveProgress()
                library.flush()
            }
        }
    }
}

// MARK: - Content

private struct HideKey: Hashable {
    var token: Int
    var shown: Bool
    var allowed: Bool
}

private struct PlayerContentView: View {
    let vm: PlayerViewModel

    @State private var controlsShown = true
    @State private var activityToken = 0
    @State private var panel: PlayerPanel?
    @State private var locked = false
    @State private var bubble: SeekBubble?
    @State private var bubbleTask: Task<Void, Never>?

    private var isPlaying: Bool { vm.state == .playing }

    private var isLoading: Bool {
        if case .loading = vm.state { return true }
        return false
    }

    /// Full controls are visible.
    private var showFull: Bool {
        isPlaying && !locked && vm.countdown == nil && (controlsShown || vm.isPaused || vm.isScrubbing)
    }

    private var autoHideAllowed: Bool {
        isPlaying && !vm.isPaused && !vm.isScrubbing && panel == nil
    }

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            surface
            if isPlaying {
                PlayerGestureLayer(onTap: handleTap, onDoubleTap: handleDoubleTap)
            }
            feedbackLayer
            controlsLayer
            lockLayer
            if isPlaying && !locked {
                PlayerPills(vm: vm, controlsShown: showFull)
                if vm.noIntroPromptVisible && panel == nil {
                    PlayerIntroPrompt(vm: vm, controlsShown: showFull) {
                        vm.dismissIntroPrompt()
                        openPanel(.introEditor)
                    }
                }
            }
            stateLayer
            if let seconds = vm.countdown {
                PlayerCountdownCard(vm: vm, seconds: seconds)
            }
            panelLayer
        }
        .environment(\.colorScheme, .dark)
        .task(id: HideKey(token: activityToken, shown: controlsShown, allowed: autoHideAllowed)) {
            guard controlsShown, autoHideAllowed else { return }
            try? await Task.sleep(nanoseconds: 3_500_000_000)
            if Task.isCancelled { return }
            withAnimation(.easeInOut(duration: 0.25)) { controlsShown = false }
        }
        .onChange(of: vm.isPaused) { _, paused in
            if paused { controlsShown = true }
            bump()
        }
        .onChange(of: controlsShown) { _, shown in
            vm.controlsVisible = shown
        }
        .onChange(of: vm.episode.id) { _, _ in
            controlsShown = true
            bump()
        }
        .onDisappear { bubbleTask?.cancel() }
    }

    // MARK: Layers

    @ViewBuilder
    private var surface: some View {
        if vm.hasItem {
            PlayerSurfaceView(
                player: vm.player,
                videoGravity: vm.videoGravity,
                onLayerReady: { layer in vm.attachLayer(layer) }
            )
            .ignoresSafeArea()
        }
    }

    private var feedbackLayer: some View {
        ZStack {
            SeekFeedbackView(bubble: bubble)
            bufferingIndicator
        }
    }

    @ViewBuilder
    private var bufferingIndicator: some View {
        if isPlaying && vm.isBuffering && !showFull {
            ProgressView()
                .progressViewStyle(.circular)
                .tint(.white)
                .scaleEffect(1.6)
                .allowsHitTesting(false)
        }
    }

    private var controlsLayer: some View {
        PlayerControlsOverlay(
            vm: vm,
            onPanel: { openPanel($0) },
            onLock: lock,
            onActivity: bump
        )
        .opacity(showFull ? 1 : 0)
        .allowsHitTesting(showFull)
        .accessibilityHidden(!showFull)
        .animation(.easeInOut(duration: 0.25), value: showFull)
    }

    @ViewBuilder
    private var lockLayer: some View {
        if isPlaying && locked {
            HStack {
                VStack {
                    Spacer(minLength: 0)
                    PlayerIconButton(systemName: "lock.open.fill", label: "Steuerung entsperren",
                                     size: 52, iconSize: 20) {
                        unlock()
                    }
                    Spacer(minLength: 0)
                }
                Spacer(minLength: 0)
            }
            .padding(.leading, 12)
            .opacity(controlsShown ? 1 : 0)
            .allowsHitTesting(controlsShown)
            .animation(.easeInOut(duration: 0.25), value: controlsShown)
        }
    }

    @ViewBuilder
    private var stateLayer: some View {
        switch vm.state {
        case .loading(let text):
            ZStack {
                PlayerLoadingView(series: vm.series, text: text)
                VStack {
                    PlayerTopBar(vm: vm, showsTools: false, onOptions: {})
                        .padding(.horizontal, 12)
                        .padding(.top, 8)
                    Spacer(minLength: 0)
                }
            }
        case .error(let message):
            PlayerErrorView(vm: vm, message: message)
        case .playing:
            EmptyView()
        }
    }

    @ViewBuilder
    private var panelLayer: some View {
        if let panel {
            PlayerPanelHost(panel: panel, vm: vm, onClose: closePanel, onOpen: { openPanel($0) })
        }
    }

    // MARK: Actions

    private func bump() {
        activityToken += 1
    }

    private func handleTap() {
        if panel != nil {
            closePanel()
            return
        }
        withAnimation(.easeInOut(duration: 0.25)) { controlsShown.toggle() }
        bump()
    }

    private func handleDoubleTap(_ side: PlayerSide) {
        switch side {
        case .center:
            vm.togglePlayPause()
        case .backward:
            seekBubble(side: .backward, delta: -10)
        case .forward:
            seekBubble(side: .forward, delta: 10)
        }
    }

    private func seekBubble(side: PlayerSide, delta: Int) {
        vm.seek(by: Double(delta))
        var total = delta
        if let current = bubble, current.side == side {
            total = current.total + delta
        }
        bubble = SeekBubble(side: side, total: total, tick: (bubble?.tick ?? 0) + 1)
        bubbleTask?.cancel()
        bubbleTask = Task {
            try? await Task.sleep(nanoseconds: 900_000_000)
            if Task.isCancelled { return }
            bubble = nil
        }
    }

    private func openPanel(_ kind: PlayerPanel) {
        withAnimation(.easeInOut(duration: 0.25)) { panel = kind }
    }

    private func closePanel() {
        withAnimation(.easeInOut(duration: 0.25)) { panel = nil }
        bump()
    }

    private func lock() {
        withAnimation(.easeInOut(duration: 0.25)) {
            locked = true
            controlsShown = true
        }
        bump()
    }

    private func unlock() {
        withAnimation(.easeInOut(duration: 0.25)) {
            locked = false
            controlsShown = true
        }
        bump()
    }
}

// MARK: - Orientation

@MainActor
enum PlayerOrientation {
    static func enterPlayer() {
        guard UIDevice.current.userInterfaceIdiom == .phone else { return }
        request(.landscape)
    }

    static func leavePlayer() {
        guard UIDevice.current.userInterfaceIdiom == .phone else { return }
        request(.portrait)
    }

    private static func request(_ mask: UIInterfaceOrientationMask) {
        let scene = UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .first { $0.activationState == .foregroundActive }
            ?? UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first
        guard let scene else { return }
        let prefs = UIWindowScene.GeometryPreferences.iOS(interfaceOrientations: mask)
        scene.requestGeometryUpdate(prefs) { _ in }
    }
}
