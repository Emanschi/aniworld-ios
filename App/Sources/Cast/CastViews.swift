import SwiftUI
import AniworldKit

/// Top-bar button that opens the device picker; filled while casting.
struct CastButton: View {
    let vm: PlayerViewModel
    @State private var showsPicker = false

    var body: some View {
        PlayerIconButton(systemName: vm.cast.isActive ? "tv.fill" : "tv", label: "Auf Fernseher streamen") {
            showsPicker = true
        }
        .sheet(isPresented: $showsPicker) {
            CastDevicePicker(vm: vm)
                .presentationDetents([.medium, .large])
                .presentationDragIndicator(.visible)
        }
    }
}

/// Lists Chromecast-compatible receivers in the Wi-Fi and explains the other options.
struct CastDevicePicker: View {
    let vm: PlayerViewModel
    @Environment(\.dismiss) private var dismiss

    private var cast: CastController { vm.cast }

    var body: some View {
        NavigationStack {
            List {
                if cast.isActive {
                    Section {
                        HStack(spacing: 12) {
                            Image(systemName: "tv.fill").foregroundStyle(Theme.accent)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(cast.deviceName).font(.headline)
                                Text(cast.phase == .connecting ? "Verbinde…" : "Wird abgespielt")
                                    .font(.footnote)
                                    .foregroundStyle(Theme.textSecondary)
                            }
                        }
                        Button(role: .destructive) {
                            vm.stopCasting()
                            dismiss()
                        } label: {
                            Label("Streamen beenden", systemImage: "stop.circle")
                        }
                    }
                }
                Section {
                    if cast.discovery.devices.isEmpty {
                        HStack(spacing: 12) {
                            ProgressView()
                            Text("Suche nach Geräten im WLAN…")
                                .foregroundStyle(Theme.textSecondary)
                        }
                    }
                    ForEach(cast.discovery.devices) { device in
                        Button {
                            vm.startCasting(to: device)
                            dismiss()
                        } label: {
                            HStack(spacing: 12) {
                                Image(systemName: "tv")
                                    .foregroundStyle(Theme.accent)
                                    .frame(width: 24)
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(device.name).foregroundStyle(.white)
                                    if let model = device.model, !model.isEmpty {
                                        Text(model)
                                            .font(.footnote)
                                            .foregroundStyle(Theme.textSecondary)
                                    }
                                }
                                Spacer()
                                if cast.device?.id == device.id && cast.isActive {
                                    Image(systemName: "checkmark").foregroundStyle(Theme.accent)
                                }
                            }
                        }
                    }
                } header: {
                    Text("Chromecast & Google TV")
                } footer: {
                    Text("iPhone und Fernseher müssen im selben WLAN sein. Beim ersten Mal fragt iOS nach dem Zugriff auf das lokale Netzwerk – bitte erlauben. Während des Streamens liefert dein iPhone das Video an den Fernseher, lass die App deshalb geöffnet oder sperr nur den Bildschirm.")
                }
                Section {
                    HStack(spacing: 12) {
                        AirPlayButton()
                            .frame(width: 28, height: 28)
                        Text("Apple TV & AirPlay-Fernseher")
                    }
                } header: {
                    Text("AirPlay")
                } footer: {
                    Text("Tippe auf das AirPlay-Symbol, um auf ein Apple TV oder einen Fernseher mit AirPlay zu streamen.")
                }
                Section {
                    Label("Installiere auf dem Fire TV eine Empfänger-App wie „AirScreen“ aus dem Amazon Appstore. Der Fire TV erscheint dann oben in der Liste oder unter AirPlay.",
                          systemImage: "flame")
                        .font(.footnote)
                        .foregroundStyle(Theme.textSecondary)
                } header: {
                    Text("Fire TV")
                }
            }
            .navigationTitle("Auf Fernseher streamen")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Fertig") { dismiss() }
                }
            }
        }
        .preferredColorScheme(.dark)
        .onAppear { cast.discovery.start() }
    }
}

/// "Fernbedienung": full-screen remote control shown in the player while the episode plays on the TV.
/// Tap = play/pause, swipe left/right = -/+10 s, swipe up/down = TV volume.
struct CastRemoteView: View {
    let vm: PlayerViewModel

    @State private var volumeBase: Double?
    @State private var flashText: String?
    @State private var flashToken = 0

    private var cast: CastController { vm.cast }

    var body: some View {
        GeometryReader { geo in
            let wide = geo.size.width > geo.size.height
            ZStack {
                AppBackground().ignoresSafeArea()
                Group {
                    if wide {
                        HStack(spacing: 28) {
                            cover(height: min(geo.size.height * 0.62, 260))
                            controls
                                .frame(maxWidth: 460)
                        }
                    } else {
                        VStack(spacing: 22) {
                            cover(height: min(geo.size.height * 0.3, 280))
                            controls
                        }
                    }
                }
                .padding(.horizontal, 24)
                .padding(.top, 56)
                .padding(.bottom, 12)

                VStack(spacing: 8) {
                    PlayerTopBar(vm: vm, showsTools: false, onOptions: {})
                        .padding(.horizontal, 12)
                        .padding(.top, 8)
                    if let notice = cast.notice {
                        noticeCard(notice)
                    }
                    Spacer(minLength: 0)
                }

                if let flashText {
                    Text(flashText)
                        .font(.system(.title3, design: .rounded).weight(.heavy))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 22)
                        .padding(.vertical, 12)
                        .background(.ultraThinMaterial, in: Capsule())
                        .overlay(Capsule().strokeBorder(Theme.accent.opacity(0.8), lineWidth: 1.5))
                        .transition(.scale(scale: 0.9).combined(with: .opacity))
                        .allowsHitTesting(false)
                }
            }
            .contentShape(Rectangle())
            .onTapGesture {
                Haptics.impact()
                vm.togglePlayPause()
            }
            .gesture(swipeGesture(height: geo.size.height))
        }
        .animation(.easeInOut(duration: 0.2), value: flashText)
        .animation(.easeInOut(duration: 0.2), value: cast.notice)
        .task(id: cast.notice) {
            guard cast.notice != nil else { return }
            try? await Task.sleep(nanoseconds: 7_000_000_000)
            if Task.isCancelled { return }
            cast.clearNotice()
        }
    }

    // MARK: Pieces

    private func cover(height: CGFloat) -> some View {
        CoverImage(url: vm.series.coverURL, title: vm.series.title, cornerRadius: 18)
            .frame(height: max(height, 120))
            .cardShadow()
            .allowsHitTesting(false)
    }

    private var controls: some View {
        VStack(spacing: 12) {
            VStack(spacing: 4) {
                Text(vm.series.title)
                    .font(.system(.title3, design: .rounded).weight(.heavy))
                    .foregroundStyle(.white)
                    .lineLimit(2)
                Text(episodeLine)
                    .font(.system(.subheadline, design: .rounded).weight(.medium))
                    .foregroundStyle(Theme.textSecondary)
                    .lineLimit(1)
                Label(statusLine, systemImage: "tv.fill")
                    .font(.system(.footnote, design: .rounded).weight(.semibold))
                    .foregroundStyle(Theme.accent)
                    .padding(.top, 2)
            }
            .multilineTextAlignment(.center)
            .allowsHitTesting(false)

            PlayerScrubber(vm: vm, onActivity: {})

            transport

            volumeRow

            HStack(spacing: 10) {
                if let pill = vm.skipPill {
                    actionPill(pill.title, systemImage: "forward.fill", accent: true) {
                        Haptics.impact()
                        vm.skipActiveOrIntro()
                    }
                }
                if vm.hasNext {
                    actionPill("Nächste Folge", systemImage: "forward.end.fill", accent: false) {
                        Haptics.impact()
                        vm.playNext()
                    }
                }
                actionPill("Beenden", systemImage: "stop.fill", accent: false) {
                    Haptics.impact()
                    vm.stopCasting()
                }
            }
        }
    }

    private var transport: some View {
        HStack(spacing: 36) {
            nudgeButton(systemName: "gobackward.10", label: "10 Sekunden zurück", delta: -10)
            Button {
                Haptics.impact()
                vm.togglePlayPause()
            } label: {
                ZStack {
                    if cast.phase == .connecting || cast.isBuffering {
                        ProgressView().tint(.white).scaleEffect(1.5)
                    } else {
                        Image(systemName: cast.isPaused ? "play.fill" : "pause.fill")
                            .font(.system(size: 34, weight: .bold))
                            .foregroundStyle(.white)
                    }
                }
                .frame(width: 80, height: 80)
                .background(Circle().fill(Theme.accentGradient))
                .shadow(color: Theme.accent.opacity(0.5), radius: 14, y: 6)
                .contentShape(Circle())
            }
            .buttonStyle(PressableStyle())
            .accessibilityLabel(cast.isPaused ? "Abspielen" : "Pause")
            nudgeButton(systemName: "goforward.10", label: "10 Sekunden vor", delta: 10)
        }
    }

    private func nudgeButton(systemName: String, label: String, delta: Double) -> some View {
        Button {
            nudge(delta)
        } label: {
            Image(systemName: systemName)
                .font(.system(size: 30, weight: .regular))
                .foregroundStyle(.white)
                .frame(width: 60, height: 60)
                .contentShape(Circle())
        }
        .buttonStyle(PressableStyle())
        .accessibilityLabel(label)
    }

    private var volumeRow: some View {
        HStack(spacing: 10) {
            Image(systemName: "speaker.fill")
                .foregroundStyle(Theme.textSecondary)
            Slider(
                value: Binding<Double>(
                    get: { cast.volume },
                    set: { cast.setVolume($0, mirrorToPhone: true) }
                ),
                in: 0...1
            )
            .tint(Theme.accent)
            Image(systemName: "speaker.wave.3.fill")
                .foregroundStyle(Theme.textSecondary)
        }
        .font(.system(size: 14))
        .disabled(!cast.hasVolume)
        .opacity(cast.hasVolume ? 1 : 0.4)
        .accessibilityLabel("Lautstärke des Fernsehers")
    }

    private func actionPill(_ title: String, systemImage: String, accent: Bool,
                            action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Label(title, systemImage: systemImage)
                .font(.system(.footnote, design: .rounded).weight(.bold))
                .foregroundStyle(.white)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
                .padding(.horizontal, 14)
                .padding(.vertical, 10)
                .background(.ultraThinMaterial, in: Capsule())
                .overlay(Capsule().strokeBorder(accent ? Theme.accent.opacity(0.9) : Color.white.opacity(0.15),
                                                lineWidth: 1.5))
                .contentShape(Capsule())
        }
        .buttonStyle(PressableStyle())
    }

    private func noticeCard(_ text: String) -> some View {
        Text(text)
            .font(.system(.footnote, design: .rounded).weight(.semibold))
            .foregroundStyle(.white)
            .multilineTextAlignment(.center)
            .padding(.horizontal, 14)
            .padding(.vertical, 9)
            .background(.ultraThinMaterial, in: Capsule())
            .padding(.horizontal, 24)
            .transition(.opacity)
            .allowsHitTesting(false)
    }

    private var episodeLine: String {
        vm.episode.title.isEmpty ? vm.episode.code : "\(vm.episode.code) · \(vm.episode.title)"
    }

    private var statusLine: String {
        if cast.phase == .connecting { return "Verbinde mit \(cast.deviceName)…" }
        return cast.isPaused ? "Pausiert auf \(cast.deviceName)" : "Läuft auf \(cast.deviceName)"
    }

    // MARK: Gestures

    private func swipeGesture(height: CGFloat) -> some Gesture {
        DragGesture(minimumDistance: 28)
            .onChanged { value in
                let dx = value.translation.width
                let dy = value.translation.height
                guard abs(dy) > abs(dx) || volumeBase != nil else { return }
                if volumeBase == nil { volumeBase = cast.volume }
                let base = volumeBase ?? cast.volume
                let level = min(max(base - Double(dy) / Double(max(height * 0.7, 200)), 0), 1)
                cast.setVolume(level, mirrorToPhone: true)
                flash("Lautstärke \(Int((level * 100).rounded())) %")
            }
            .onEnded { value in
                let dx = value.translation.width
                let dy = value.translation.height
                let wasVolume = volumeBase != nil
                volumeBase = nil
                guard !wasVolume, abs(dx) > abs(dy), abs(dx) > 60 else { return }
                nudge(dx > 0 ? 10 : -10)
            }
    }

    private func nudge(_ delta: Double) {
        Haptics.impact()
        vm.seek(by: delta)
        flash(delta > 0 ? "+\(Int(delta)) s" : "−\(Int(-delta)) s")
    }

    private func flash(_ text: String) {
        flashText = text
        flashToken += 1
        let token = flashToken
        Task {
            try? await Task.sleep(nanoseconds: 900_000_000)
            if flashToken == token { flashText = nil }
        }
    }
}

/// Short error card when casting failed; tap to dismiss.
struct CastErrorBanner: View {
    let message: String
    let onDismiss: () -> Void

    var body: some View {
        VStack {
            Button(action: onDismiss) {
                HStack(spacing: 10) {
                    Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(.orange)
                    Text(message)
                        .font(.system(.subheadline, design: .rounded).weight(.semibold))
                        .foregroundStyle(.white)
                        .multilineTextAlignment(.leading)
                    Spacer(minLength: 4)
                    Image(systemName: "xmark").font(.caption.weight(.bold)).foregroundStyle(.white.opacity(0.7))
                }
                .padding(14)
                .frame(maxWidth: 460)
                .background(RoundedRectangle(cornerRadius: 16, style: .continuous).fill(.ultraThinMaterial))
            }
            .buttonStyle(PressableStyle())
            .padding(.horizontal, 16)
            .padding(.top, 20)
            Spacer(minLength: 0)
        }
        .transition(.move(edge: .top).combined(with: .opacity))
        .task {
            try? await Task.sleep(nanoseconds: 8_000_000_000)
            if Task.isCancelled { return }
            onDismiss()
        }
    }
}
