import SwiftUI

/// Side panel to define or correct intro/outro times while the video keeps playing.
struct PlayerIntroEditorPanel: View {
    let vm: PlayerViewModel
    let onClose: () -> Void

    @State private var introStart: Double?
    @State private var introEnd: Double?
    @State private var outroStart: Double?
    @State private var outroEnd: Double?
    @State private var wholeSeason = true
    @State private var loaded = false

    private var duration: Double { vm.duration }

    private var introTouched: Bool { introStart != nil || introEnd != nil }
    private var outroTouched: Bool { outroStart != nil || outroEnd != nil }

    /// Returns a German error text, or nil when the input can be saved.
    private var validationError: String? {
        if !introTouched && !outroTouched {
            return "Lege Intro oder Outro (Anfang und Ende) fest."
        }
        if introTouched {
            guard let s = introStart, let e = introEnd else { return "Intro: Anfang und Ende werden benötigt." }
            if e <= s { return "Intro: Das Ende muss nach dem Anfang liegen." }
            if duration > 0 && e > duration { return "Intro: Das Ende liegt hinter der Folgenlänge." }
        }
        if outroTouched {
            guard let s = outroStart, let e = outroEnd else { return "Outro: Anfang und Ende werden benötigt." }
            if e <= s { return "Outro: Das Ende muss nach dem Anfang liegen." }
            if duration > 0 && e > duration { return "Outro: Das Ende liegt hinter der Folgenlänge." }
        }
        return nil
    }

    var body: some View {
        VStack(spacing: 0) {
            PlayerPanelHeader(title: "Intro & Outro bearbeiten",
                              subtitle: "\(vm.series.title) · \(vm.episode.code)",
                              onClose: onClose)
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    if !vm.hasKnownIntro && vm.customSkip == nil {
                        Text("Für diese Folge ist noch kein Intro hinterlegt. Spiele bis zum Intro-Anfang und übernimm die Position.")
                            .font(.system(.footnote, design: .rounded))
                            .foregroundStyle(Theme.textSecondary)
                    }
                    PlayerTimeAdjustRow(title: "Intro-Anfang", value: $introStart, vm: vm)
                    PlayerTimeAdjustRow(title: "Intro-Ende", value: $introEnd, vm: vm)

                    Text("OUTRO (OPTIONAL)")
                        .font(.system(.caption, design: .rounded).weight(.bold))
                        .foregroundStyle(Theme.textTertiary)
                        .padding(.top, 4)
                    PlayerTimeAdjustRow(title: "Outro-Anfang", value: $outroStart, vm: vm)
                    PlayerTimeAdjustRow(title: "Outro-Ende", value: $outroEnd, vm: vm)

                    Text("GELTUNGSBEREICH")
                        .font(.system(.caption, design: .rounded).weight(.bold))
                        .foregroundStyle(Theme.textTertiary)
                        .padding(.top, 4)
                    Picker("Geltungsbereich", selection: $wholeSeason) {
                        Text("Ganze Staffel").tag(true)
                        Text("Nur diese Folge").tag(false)
                    }
                    .pickerStyle(.segmented)

                    if let error = validationError, introTouched || outroTouched {
                        Text(error)
                            .font(.system(.footnote, design: .rounded))
                            .foregroundStyle(Color.red)
                    }

                    Button {
                        save()
                    } label: {
                        Text("Speichern")
                            .font(.system(.body, design: .rounded).weight(.bold))
                            .foregroundStyle(.white)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 13)
                            .background(
                                RoundedRectangle(cornerRadius: 12, style: .continuous)
                                    .fill(Theme.accent.opacity(validationError == nil ? 1 : 0.35))
                            )
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(PressableStyle())
                    .disabled(validationError != nil)

                    if vm.customSkip != nil {
                        Button {
                            vm.deleteCustomSkip()
                            onClose()
                        } label: {
                            Text("Löschen")
                                .font(.system(.body, design: .rounded).weight(.bold))
                                .foregroundStyle(Color.red)
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 13)
                                .background(
                                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                                        .fill(Theme.surfaceHigh.opacity(0.6))
                                )
                                .contentShape(Rectangle())
                        }
                        .buttonStyle(PressableStyle())
                    }
                }
                .padding(.horizontal, 14)
                .padding(.bottom, 20)
            }
        }
        .onAppear { loadInitialValues() }
    }

    private func loadInitialValues() {
        guard !loaded else { return }
        loaded = true
        let d = vm.editorDefaults
        introStart = d.introStart
        introEnd = d.introEnd
        outroStart = d.outroStart
        outroEnd = d.outroEnd
        if let existing = vm.customSkip {
            wholeSeason = existing.episode == nil
        } else {
            wholeSeason = true
        }
    }

    private func save() {
        guard validationError == nil else { return }
        vm.saveCustomSkip(
            wholeSeason: wholeSeason,
            introStart: introTouched ? introStart : nil,
            introEnd: introTouched ? introEnd : nil,
            outroStart: outroTouched ? outroStart : nil,
            outroEnd: outroTouched ? outroEnd : nil
        )
        onClose()
    }
}

/// One time value (mm:ss) with "Aktuelle Position" and ±1 s / ±5 s buttons.
struct PlayerTimeAdjustRow: View {
    let title: String
    @Binding var value: Double?
    let vm: PlayerViewModel

    private func clampedValue(_ seconds: Double) -> Double {
        var t = max(seconds, 0)
        if vm.duration > 0 { t = min(t, vm.duration) }
        return (t * 10).rounded() / 10
    }

    private func shift(_ delta: Double) {
        let base = value ?? vm.position
        value = clampedValue(base + delta)
    }

    private var valueText: String {
        guard let value else { return "–:––" }
        return PlayerFormat.time(value)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(title)
                    .font(.system(.subheadline, design: .rounded).weight(.bold))
                    .foregroundStyle(.white)
                Spacer(minLength: 8)
                Text(valueText)
                    .font(.system(.title3, design: .rounded).weight(.bold).monospacedDigit())
                    .foregroundStyle(value == nil ? Theme.textTertiary : Theme.accent)
            }
            HStack(spacing: 6) {
                stepButton("−5", -5)
                stepButton("−1", -1)
                Button {
                    value = clampedValue(vm.position)
                } label: {
                    Text("Aktuelle Position")
                        .font(.system(.caption, design: .rounded).weight(.bold))
                        .foregroundStyle(.white)
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 9)
                        .background(Capsule().fill(Theme.accent.opacity(0.8)))
                        .contentShape(Capsule())
                }
                .buttonStyle(PressableStyle())
                stepButton("+1", 1)
                stepButton("+5", 5)
            }
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(Theme.surfaceHigh.opacity(0.6))
        )
    }

    private func stepButton(_ label: String, _ delta: Double) -> some View {
        Button {
            shift(delta)
        } label: {
            Text(label)
                .font(.system(.caption, design: .rounded).weight(.bold).monospacedDigit())
                .foregroundStyle(.white)
                .frame(width: 34)
                .padding(.vertical, 9)
                .background(Capsule().fill(Color.white.opacity(0.12)))
                .contentShape(Capsule())
        }
        .buttonStyle(PressableStyle())
        .accessibilityLabel("\(Int(delta)) Sekunden")
    }
}
