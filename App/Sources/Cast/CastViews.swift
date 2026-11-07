import SwiftUI

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

/// Shown over the (paused) video while it plays on the TV.
struct CastActiveOverlay: View {
    let cast: CastController

    var body: some View {
        VStack(spacing: 12) {
            Image(systemName: "tv.fill")
                .font(.system(size: 44, weight: .semibold))
                .foregroundStyle(Theme.accentGradient)
            Text(cast.phase == .connecting ? "Verbinde mit \(cast.deviceName)…" : "Wird auf \(cast.deviceName) abgespielt")
                .font(.system(.headline, design: .rounded).weight(.bold))
                .foregroundStyle(.white)
                .multilineTextAlignment(.center)
            if cast.isBuffering {
                ProgressView().tint(.white)
            }
        }
        .padding(24)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.black.opacity(0.85))
        .allowsHitTesting(false)
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
