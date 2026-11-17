import SwiftUI

/// "Du schaust über mobile Daten": shown once per app session while streaming over mobile data.
/// Playback is paused until the user continues.
struct CellularWarningCard: View {
    let vm: PlayerViewModel

    @Environment(SettingsStore.self) private var settings

    var body: some View {
        @Bindable var settings = settings
        ZStack {
            Color.black.opacity(0.62)
                .ignoresSafeArea()
                .contentShape(Rectangle())
                .onTapGesture {}

            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    HStack(spacing: 12) {
                        Image(systemName: "antenna.radiowaves.left.and.right")
                            .font(.system(size: 22, weight: .bold))
                            .foregroundStyle(.white)
                            .frame(width: 44, height: 44)
                            .background(Theme.accentGradient, in: Circle())
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Du schaust über mobile Daten")
                                .font(.system(.headline, design: .rounded).weight(.heavy))
                                .foregroundStyle(.white)
                            Text("Streaming verbraucht viel Datenvolumen.")
                                .font(.subheadline)
                                .foregroundStyle(Theme.textSecondary)
                        }
                    }

                    VStack(alignment: .leading, spacing: 4) {
                        Text("Diese Folge: \(StreamDataFormat.approx(bytes: vm.cellularEstimateBytes))")
                            .font(.system(.title3, design: .rounded).weight(.bold))
                            .foregroundStyle(.white)
                        Text("Geschätzt bei „\(settings.streamQualityCellular.title)“, \(settings.streamQualityCellular.dataPerHourText).")
                            .font(.caption)
                            .foregroundStyle(Theme.textSecondary)
                    }

                    HStack {
                        Text("Qualität über mobile Daten")
                            .font(.subheadline)
                            .foregroundStyle(.white)
                        Spacer(minLength: 8)
                        Picker("Qualität", selection: $settings.streamQualityCellular) {
                            ForEach(StreamQuality.allCases) { quality in
                                Text("\(quality.title) · \(quality.dataPerHourText)").tag(quality)
                            }
                        }
                        .pickerStyle(.menu)
                        .tint(Theme.accent)
                    }

                    if !vm.streamIsAdaptive {
                        Text("Dieser Hoster liefert nur eine einzige Qualität. Die Auswahl wirkt bei Streams mit mehreren Qualitätsstufen, bei dieser Folge nicht.")
                            .font(.caption)
                            .foregroundStyle(Theme.textTertiary)
                    }

                    Button {
                        Haptics.impact()
                        vm.dismissCellularWarning()
                    } label: {
                        Text("Weiter schauen")
                            .font(.headline)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 12)
                            .background(Theme.accentGradient, in: Capsule())
                            .foregroundStyle(.white)
                    }
                    .buttonStyle(PressableStyle())

                    Button {
                        vm.dismissCellularWarning(disableFuture: true)
                    } label: {
                        Text("Nicht mehr fragen")
                            .font(.subheadline.weight(.semibold))
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 6)
                            .foregroundStyle(Theme.textSecondary)
                    }
                    .buttonStyle(.plain)
                }
                .padding(18)
                .frame(maxWidth: 460)
                .background(
                    RoundedRectangle(cornerRadius: 22, style: .continuous)
                        .fill(Theme.surface)
                        .overlay(
                            RoundedRectangle(cornerRadius: 22, style: .continuous)
                                .strokeBorder(Theme.accent.opacity(0.5), lineWidth: 1)
                        )
                )
                .padding(.horizontal, 16)
                .padding(.vertical, 20)
                .frame(maxWidth: .infinity)
            }
            .scrollBounceBehavior(.basedOnSize)
        }
        .transition(.opacity)
        .accessibilityAddTraits(.isModal)
    }
}
