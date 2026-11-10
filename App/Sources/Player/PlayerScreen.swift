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
    @Environment(DownloadManager.self) private var downloads
    @Environment(WatchStatsStore.self) private var stats
    @Environment(\.aniworld) private var service
    @Environment(\.scenePhase) private var scenePhase

    @State private var viewModel: PlayerViewModel?
    @State private var originalBrightness: CGFloat?
    /// Brightness chosen in the player, re-applied when the app becomes active again.
    @State private var playerBrightness: CGFloat?

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            SystemVolumeView()
                .frame(width: 0, height: 0)
                .allowsHitTesting(false)
            if let viewModel {
                PlayerContentView(vm: viewModel)
            }
        }
        .statusBarHidden(!playback.isMinimized)
        .persistentSystemOverlays(playback.isMinimized ? .automatic : .hidden)
        .task {
            guard viewModel == nil else { return }
            let vm = PlayerViewModel(session: session)
            vm.attach(service: service, library: library, settings: settings, coordinator: playback,
                      downloads: downloads, stats: stats)
            viewModel = vm
            vm.start()
        }
        .onAppear {
            if originalBrightness == nil { originalBrightness = UIScreen.main.brightness }
            PlayerOrientation.enterPlayer()
        }
        .onDisappear {
            if let orig = originalBrightness {
                UIScreen.main.brightness = orig
            }
            viewModel?.shutdown()
            PlayerOrientation.leavePlayer()
        }
        .onChange(of: scenePhase) { _, phase in
            if phase != .active {
                viewModel?.saveProgress()
                library.flush()
                if phase == .background { viewModel?.flushStats() }
            }
            updateBrightness()
        }
        // Minimized = Picture in Picture is playing while the user browses the app.
        .onChange(of: playback.isMinimized) { _, minimized in
            if minimized { PlayerOrientation.leavePlayer() } else { PlayerOrientation.enterPlayer() }
            updateBrightness()
        }
        // The PiP button keeps the app active, so the scene phase alone does not cover it.
        .onChange(of: viewModel?.isPictureInPictureActive ?? false) { _, _ in
            updateBrightness()
        }
    }

    /// Screen brightness is a system-wide setting: the player's own value only applies while the
    /// full-screen player is in front. In the background, the app switcher or Picture in Picture
    /// (button or swipe) the original brightness is given back, and re-applied on return.
    private func updateBrightness() {
        let playerInFront = scenePhase == .active && viewModel?.isPictureInPictureActive != true
        if !playerInFront {
            guard let orig = originalBrightness, playerBrightness == nil else { return }
            let current = UIScreen.main.brightness
            if abs(current - orig) > 0.001 {
                playerBrightness = current
                UIScreen.main.brightness = orig
            }
        } else if let custom = playerBrightness {
            UIScreen.main.brightness = custom
            playerBrightness = nil
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
    @State private var hudState: PlayerHUDState?
    @State private var hudDismissTask: Task<Void, Never>?
    @State private var isActivelySwiping = false
    @State private var lastSwipeAt = Date.distantPast
    @State private var baseBrightness: Double = 0.5
    @State private var baseVolume: Double = 0.5

    private var isPlaying: Bool { vm.state == .playing }

    private var isLoading: Bool {
        if case .loading = vm.state { return true }
        return false
    }

    /// Full controls are visible.
    private var showFull: Bool {
        isPlaying && !locked && !vm.cast.isActive && vm.countdown == nil && (controlsShown || vm.isPaused || vm.isScrubbing)
    }

    private var showNextPill: Bool {
        vm.hasNext && vm.countdown == nil && vm.duration > 0 && vm.duration - vm.position < 120
    }

    private var autoHideAllowed: Bool {
        isPlaying && !vm.isPaused && !vm.isScrubbing && panel == nil
    }

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            surface
            if isPlaying && !vm.cast.isActive {
                PlayerGestureLayer(
                    onTap: handleTap,
                    onDoubleTap: handleDoubleTap,
                    onVerticalSwipe: handleVerticalSwipe,
                    onSwipeEnd: handleSwipeEnd
                )
            }
            if vm.cast.isActive {
                CastRemoteView(vm: vm)
            }
            feedbackLayer
            if let hudState {
                HStack {
                    if hudState.kind == .brightness {
                        PlayerHUDBar(state: hudState)
                            .padding(.leading, 36)
                        Spacer()
                    } else {
                        Spacer()
                        PlayerHUDBar(state: hudState)
                            .padding(.trailing, 36)
                    }
                }
                .transition(.opacity.combined(with: .scale(scale: 0.95)))
                .allowsHitTesting(false)
                .zIndex(8)
            }
            controlsLayer
            lockLayer
            if isPlaying && !locked && !vm.cast.isActive {
                PlayerPills(
                    skip: vm.skipPill,
                    showNext: showNextPill,
                    onSkip: { vm.skipActiveOrIntro() },
                    onNext: { vm.playNext() },
                    controlsShown: showFull
                )
                .zIndex(2)
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
            if let days = vm.streakCelebration, !locked {
                StreakCelebrationBanner(days: days) {
                    withAnimation(.easeInOut(duration: 0.25)) { vm.dismissStreakCelebration() }
                }
                .zIndex(9)
            }
            if case .failed(let message) = vm.cast.phase {
                CastErrorBanner(message: message) {
                    withAnimation(.easeInOut(duration: 0.25)) { vm.cast.dismissError() }
                }
                .zIndex(9)
            }
            panelLayer
        }
        .animation(.spring(response: 0.4, dampingFraction: 0.8), value: vm.streakCelebration)
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
        .task {
            // Hardware volume buttons: the hidden MPVolumeView suppresses the system HUD, so show ours.
            // Cancelled with the view, which ends the stream and invalidates the KVO observation.
            let stream = AsyncStream<Float> { continuation in
                let observation = AVAudioSession.sharedInstance().observe(\.outputVolume, options: [.new]) { _, change in
                    if let value = change.newValue { continuation.yield(value) }
                }
                continuation.onTermination = { _ in observation.invalidate() }
            }
            for await value in stream {
                handleHardwareVolume(Double(value))
            }
        }
        .onDisappear {
            bubbleTask?.cancel()
            hudDismissTask?.cancel()
        }
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

    private func handleVerticalSwipe(isLeft: Bool, deltaFraction: Double) {
        guard !locked else { return }
        lastSwipeAt = Date()
        if !isActivelySwiping {
            isActivelySwiping = true
            baseBrightness = Double(UIScreen.main.brightness)
            baseVolume = Double(VolumeController.shared.currentVolume)
            hudDismissTask?.cancel()
        }

        if isLeft {
            let target = min(max(baseBrightness + deltaFraction, 0), 1)
            UIScreen.main.brightness = CGFloat(target)
            withAnimation(.spring(response: 0.2, dampingFraction: 0.8)) {
                hudState = PlayerHUDState(kind: .brightness, value: target)
            }
        } else {
            let target = min(max(baseVolume + deltaFraction, 0), 1)
            VolumeController.shared.setVolume(Float(target))
            withAnimation(.spring(response: 0.2, dampingFraction: 0.8)) {
                hudState = PlayerHUDState(kind: .volume, value: target)
            }
        }
        bump()
    }

    private func handleSwipeEnd() {
        isActivelySwiping = false
        lastSwipeAt = Date()
        scheduleHUDDismiss()
    }

    private func scheduleHUDDismiss() {
        hudDismissTask?.cancel()
        hudDismissTask = Task {
            try? await Task.sleep(nanoseconds: 1_200_000_000)
            if Task.isCancelled { return }
            withAnimation(.easeOut(duration: 0.25)) {
                hudState = nil
            }
        }
    }

    /// Volume changed through the hardware buttons (or the system). Ignores changes caused by our
    /// own swipe, which arrive slightly delayed through the hidden volume slider.
    private func handleHardwareVolume(_ value: Double) {
        if vm.cast.isActive {
            // While casting, the iPhone's volume buttons control the TV. Echoes of our own slider
            // changes (mirrored to the phone) are ignored.
            guard vm.cast.hasVolume, Date().timeIntervalSince(vm.cast.lastVolumeSetAt) > 0.8 else { return }
            vm.cast.setVolume(value, mirrorToPhone: false)
            return
        }
        guard !isActivelySwiping, !locked, Date().timeIntervalSince(lastSwipeAt) > 0.6 else { return }
        withAnimation(.spring(response: 0.2, dampingFraction: 0.8)) {
            hudState = PlayerHUDState(kind: .volume, value: min(max(value, 0), 1))
        }
        bump()
        scheduleHUDDismiss()
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
