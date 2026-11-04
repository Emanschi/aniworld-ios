import SwiftUI
import AniworldKit

/// List of the season's episodes; the current one is highlighted, a tap starts it.
struct PlayerEpisodePanel: View {
    let vm: PlayerViewModel
    let onClose: () -> Void

    private var subtitle: String {
        let season = vm.episode.season
        return season == 0 ? "Filme" : "Staffel \(season)"
    }

    var body: some View {
        VStack(spacing: 0) {
            PlayerPanelHeader(title: "Folgen", subtitle: subtitle, onClose: onClose)
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(spacing: 8) {
                        ForEach(vm.seasonEpisodes) { ep in
                            row(ep)
                                .id(ep.id)
                        }
                    }
                    .padding(.horizontal, 14)
                    .padding(.bottom, 20)
                }
                .onAppear {
                    proxy.scrollTo(vm.episode.id, anchor: .center)
                }
            }
        }
    }

    private func row(_ ep: EpisodeRef) -> some View {
        let isCurrent = ep.id == vm.episode.id
        return Button {
            if !isCurrent { vm.playEpisode(ep) }
            onClose()
        } label: {
            HStack(spacing: 12) {
                Text("\(ep.number)")
                    .font(.system(.headline, design: .rounded).weight(.heavy))
                    .monospacedDigit()
                    .foregroundStyle(isCurrent ? Color.white : Theme.textSecondary)
                    .frame(width: 34, height: 34)
                    .background(
                        Circle().fill(isCurrent ? AnyShapeStyle(Theme.accentGradient) : AnyShapeStyle(Theme.surfaceHigh))
                    )
                VStack(alignment: .leading, spacing: 2) {
                    Text(ep.title.isEmpty ? ep.code : ep.title)
                        .font(.system(.subheadline, design: .rounded).weight(.semibold))
                        .foregroundStyle(.white)
                        .lineLimit(2)
                        .multilineTextAlignment(.leading)
                    Text(isCurrent ? "\(ep.code) · Läuft gerade" : ep.code)
                        .font(.system(.caption, design: .rounded))
                        .foregroundStyle(isCurrent ? Theme.accent : Theme.textTertiary)
                }
                Spacer(minLength: 6)
                if isCurrent {
                    Image(systemName: "waveform")
                        .font(.system(size: 14, weight: .bold))
                        .foregroundStyle(Theme.accent)
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .background(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(isCurrent ? Theme.accent.opacity(0.18) : Theme.surfaceHigh.opacity(0.6))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .strokeBorder(isCurrent ? Theme.accent.opacity(0.7) : Color.clear, lineWidth: 1)
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(PressableStyle())
        .accessibilityAddTraits(isCurrent ? .isSelected : [])
    }
}
