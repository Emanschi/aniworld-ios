import SwiftUI
import AVKit
import AniworldKit

/// Full-screen player: native `AVPlayerViewController` with a SwiftUI overlay on top.
/// The overlay follows the visibility of the native transport controls, so it never
/// competes with their tap handling.
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

private struct PlayerContentView: View {
    let vm: PlayerViewModel

    private var isPlaying: Bool { vm.state == .playing }
    /// Chrome is shown with the native controls, while paused, loading or on error.
    private var showChrome: Bool { vm.controlsVisible || vm.isPaused || !isPlaying }

    var body: some View {
        ZStack {
            if vm.hasItem {
                NativePlayerView(
                    player: vm.player,
                    onControlsVisibility: { vm.controlsVisible = $0 },
                    onPictureInPicture: { vm.isPictureInPictureActive = $0 }
                )
                .ignoresSafeArea()
            }

            switch vm.state {
            case .loading(let text):
                loadingView(text)
            case .error(let message):
                errorView(message)
            case .playing:
                EmptyView()
            }

            chrome
                .opacity(showChrome ? 1 : 0)
                .allowsHitTesting(showChrome)
                .animation(.easeInOut(duration: 0.2), value: showChrome)

            if let seconds = vm.countdown {
                countdownCard(seconds)
            }
        }
    }

    // MARK: Chrome (top bar + bottom-trailing buttons)

    private var chrome: some View {
        VStack(spacing: 0) {
            topBar
            Spacer(minLength: 0)
            if isPlaying { bottomButtons }
        }
        .padding(.horizontal, 12)
        .padding(.top, 8)
        .padding(.bottom, 96)
    }

    private var topBar: some View {
        HStack(alignment: .top, spacing: 10) {
            Button {
                vm.close()
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 16, weight: .bold))
                    .frame(width: 38, height: 38)
                    .background(.ultraThinMaterial, in: Circle())
            }
            .accessibilityLabel("Schließen")

            VStack(alignment: .leading, spacing: 2) {
                Text(vm.series.title)
                    .font(.subheadline.weight(.semibold))
                    .lineLimit(1)
                Text(episodeLine)
                    .font(.caption)
                    .foregroundStyle(.white.opacity(0.8))
                    .lineLimit(1)
            }
            .shadow(color: .black.opacity(0.6), radius: 3)

            Spacer(minLength: 8)

            if !vm.availableLanguages.isEmpty || !vm.availableHosters.isEmpty {
                optionsMenu
            }
        }
        .foregroundStyle(.white)
    }

    private var episodeLine: String {
        vm.episode.title.isEmpty ? vm.episode.code : "\(vm.episode.code) – \(vm.episode.title)"
    }

    private var optionsMenu: some View {
        Menu {
            if !vm.availableLanguages.isEmpty {
                Section("Sprache") {
                    ForEach(vm.availableLanguages, id: \.self) { language in
                        Button {
                            vm.switchLanguage(language)
                        } label: {
                            if language == vm.currentLanguage {
                                Label(language.displayName, systemImage: "checkmark")
                            } else {
                                Text(language.displayName)
                            }
                        }
                    }
                }
            }
            if !vm.availableHosters.isEmpty {
                Section("Hoster") {
                    ForEach(vm.availableHosters, id: \.self) { name in
                        Button {
                            vm.switchHoster(name)
                        } label: {
                            if name == vm.currentHoster {
                                Label(name, systemImage: "checkmark")
                            } else {
                                Text(name)
                            }
                        }
                    }
                }
            }
        } label: {
            Image(systemName: "ellipsis")
                .font(.system(size: 16, weight: .bold))
                .frame(width: 38, height: 38)
                .background(.ultraThinMaterial, in: Circle())
        }
        .accessibilityLabel("Sprache und Hoster")
    }

    private var showSkipIntro: Bool {
        vm.position < 240 && vm.duration > Double(vm.introSkipSeconds) + 120
    }

    private var showNextButton: Bool {
        vm.hasNext && vm.countdown == nil && vm.duration > 0 && vm.duration - vm.position < 120
    }

    private var bottomButtons: some View {
        HStack(spacing: 10) {
            Spacer(minLength: 0)
            if showSkipIntro {
                pillButton("Intro überspringen", systemImage: "forward.fill") { vm.skipIntro() }
            }
            if showNextButton {
                pillButton("Nächste Folge", systemImage: "forward.end.fill") { vm.playNext() }
            }
        }
    }

    private func pillButton(_ title: String, systemImage: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Label(title, systemImage: systemImage)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.white)
                .padding(.horizontal, 14)
                .padding(.vertical, 9)
                .background(.ultraThinMaterial, in: Capsule())
        }
    }

    // MARK: States

    private func loadingView(_ text: String) -> some View {
        VStack(spacing: 14) {
            ProgressView()
                .progressViewStyle(.circular)
                .tint(.white)
                .scaleEffect(1.3)
            Text(text)
                .font(.subheadline)
                .foregroundStyle(.white.opacity(0.85))
        }
        .padding(24)
        .allowsHitTesting(false)
    }

    private func errorView(_ message: String) -> some View {
        VStack(spacing: 16) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 34))
                .foregroundStyle(.yellow)
            Text("Wiedergabe nicht möglich")
                .font(.headline)
            Text(message)
                .font(.subheadline)
                .multilineTextAlignment(.center)
                .foregroundStyle(.white.opacity(0.8))
            VStack(spacing: 10) {
                Button { vm.retry() } label: {
                    Text("Erneut versuchen").frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                Button { vm.tryOtherHoster() } label: {
                    Text("Anderen Hoster versuchen").frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
                Button { vm.close() } label: {
                    Text("Schließen").frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
                .tint(.white)
            }
            .frame(maxWidth: 320)
        }
        .foregroundStyle(.white)
        .padding(24)
    }

    private func countdownCard(_ seconds: Int) -> some View {
        VStack(spacing: 12) {
            Text("Nächste Folge in \(seconds) s")
                .font(.headline)
            HStack(spacing: 10) {
                Button { vm.cancelCountdown() } label: {
                    Text("Abbrechen").padding(.horizontal, 6)
                }
                .buttonStyle(.bordered)
                .tint(.white)
                Button { vm.playNext() } label: {
                    Text("Jetzt abspielen").padding(.horizontal, 6)
                }
                .buttonStyle(.borderedProminent)
            }
        }
        .foregroundStyle(.white)
        .padding(20)
        .background(.black.opacity(0.75), in: RoundedRectangle(cornerRadius: 16))
    }
}

// MARK: - Native player

private struct NativePlayerView: UIViewControllerRepresentable {
    let player: AVPlayer
    var onControlsVisibility: (Bool) -> Void
    var onPictureInPicture: (Bool) -> Void

    func makeCoordinator() -> Coordinator { Coordinator() }

    func makeUIViewController(context: Context) -> AVPlayerViewController {
        let vc = AVPlayerViewController()
        vc.player = player
        vc.delegate = context.coordinator
        vc.showsPlaybackControls = true
        vc.allowsPictureInPicturePlayback = true
        vc.canStartPictureInPictureAutomaticallyFromInline = true
        vc.updatesNowPlayingInfoCenter = true
        vc.entersFullScreenWhenPlaybackBegins = false
        vc.videoGravity = .resizeAspect
        vc.view.backgroundColor = .black
        context.coordinator.onControlsVisibility = onControlsVisibility
        context.coordinator.onPictureInPicture = onPictureInPicture
        return vc
    }

    func updateUIViewController(_ vc: AVPlayerViewController, context: Context) {
        if vc.player !== player { vc.player = player }
        context.coordinator.onControlsVisibility = onControlsVisibility
        context.coordinator.onPictureInPicture = onPictureInPicture
    }

    @MainActor
    final class Coordinator: NSObject, AVPlayerViewControllerDelegate {
        var onControlsVisibility: (Bool) -> Void = { _ in }
        var onPictureInPicture: (Bool) -> Void = { _ in }

        func playerViewController(_ playerViewController: AVPlayerViewController,
                                  willTransitionToVisibilityOfTransportControls visible: Bool,
                                  with coordinator: any AVPlayerViewControllerAnimationCoordinator) {
            onControlsVisibility(visible)
        }

        func playerViewControllerWillStartPictureInPicture(_ playerViewController: AVPlayerViewController) {
            onPictureInPicture(true)
        }

        func playerViewControllerDidStopPictureInPicture(_ playerViewController: AVPlayerViewController) {
            onPictureInPicture(false)
        }

        func playerViewController(
            _ playerViewController: AVPlayerViewController,
            restoreUserInterfaceForPictureInPictureStopWithCompletionHandler completionHandler: @escaping (Bool) -> Void
        ) {
            // The full-screen cover is still presented, so there is nothing to rebuild.
            completionHandler(true)
        }
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
