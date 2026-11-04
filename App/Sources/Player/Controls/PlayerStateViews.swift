import SwiftUI
import AniworldKit

/// Loading screen: blurred series cover, poster, spinner and step text.
struct PlayerLoadingView: View {
    let series: SeriesSummary
    let text: String

    var body: some View {
        ZStack {
            background
            VStack(spacing: 16) {
                SeriesCover(series: series, aspect: 2.0 / 3.0, cornerRadius: 12)
                    .frame(width: 96)
                    .shadow(color: .black.opacity(0.5), radius: 14, y: 8)
                ProgressView()
                    .progressViewStyle(.circular)
                    .tint(.white)
                    .scaleEffect(1.3)
                Text(text)
                    .font(.system(.subheadline, design: .rounded).weight(.semibold))
                    .foregroundStyle(.white.opacity(0.9))
                    .multilineTextAlignment(.center)
            }
            .padding(24)
        }
        .allowsHitTesting(false)
    }

    private var background: some View {
        ZStack {
            Color.black
            Color.clear
                .overlay {
                    ZStack {
                        CoverPlaceholder(title: series.title)
                        CachedImage(url: series.coverURL)
                    }
                }
                .clipped()
                .blur(radius: 40)
                .opacity(0.45)
            LinearGradient(colors: [Color.black.opacity(0.5), Color.black.opacity(0.85)],
                           startPoint: .top, endPoint: .bottom)
        }
        .ignoresSafeArea()
    }
}

/// Error screen with retry / other hoster / close.
struct PlayerErrorView: View {
    let vm: PlayerViewModel
    let message: String

    var body: some View {
        ZStack {
            Color.black.opacity(0.88).ignoresSafeArea()
            VStack(spacing: 14) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .font(.system(size: 34))
                    .foregroundStyle(Theme.accentPink)
                Text("Wiedergabe nicht möglich")
                    .font(AppFont.sectionTitle)
                Text(message)
                    .font(.system(.subheadline, design: .rounded))
                    .multilineTextAlignment(.center)
                    .foregroundStyle(Theme.textSecondary)
                    .lineLimit(5)
                VStack(spacing: 10) {
                    Button { vm.retry() } label: {
                        Text("Erneut versuchen").frame(maxWidth: .infinity)
                    }
                    .buttonStyle(AccentButtonStyle())
                    secondaryButton("Anderen Hoster versuchen") { vm.tryOtherHoster() }
                    secondaryButton("Schließen") { vm.close() }
                }
                .padding(.top, 6)
            }
            .foregroundStyle(.white)
            .padding(24)
            .frame(maxWidth: 380)
            .background(
                RoundedRectangle(cornerRadius: 22, style: .continuous)
                    .fill(Theme.surface)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 22, style: .continuous)
                    .strokeBorder(Color.white.opacity(0.08), lineWidth: 1)
            )
            .padding(20)
        }
    }

    private func secondaryButton(_ title: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .font(.system(.headline, design: .rounded))
                .foregroundStyle(.white)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 12)
                .background(Capsule().fill(Theme.surfaceHigh))
        }
        .buttonStyle(PressableStyle())
    }
}

/// Autoplay countdown card (bottom right) with a progress ring.
struct PlayerCountdownCard: View {
    let vm: PlayerViewModel
    let seconds: Int

    @State private var total: Int = 0

    private var nextEpisode: EpisodeRef? {
        guard let index = vm.seasonEpisodes.firstIndex(where: { $0.id == vm.episode.id }),
              index + 1 < vm.seasonEpisodes.count else { return nil }
        return vm.seasonEpisodes[index + 1]
    }

    private var fraction: Double {
        let base = max(total, seconds, 1)
        return Double(seconds) / Double(base)
    }

    var body: some View {
        VStack {
            Spacer(minLength: 0)
            HStack {
                Spacer(minLength: 0)
                card
            }
        }
        .padding(.trailing, 20)
        .padding(.bottom, 24)
        .onAppear { total = max(total, seconds) }
        .transition(.move(edge: .trailing).combined(with: .opacity))
    }

    private var card: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 12) {
                thumbnail
                VStack(alignment: .leading, spacing: 3) {
                    Text("Als Nächstes")
                        .font(.system(.caption, design: .rounded).weight(.bold))
                        .foregroundStyle(Theme.accent)
                    Text(nextTitle)
                        .font(.system(.subheadline, design: .rounded).weight(.bold))
                        .lineLimit(2)
                    Text("in \(seconds) s")
                        .font(.system(.caption, design: .rounded))
                        .foregroundStyle(Theme.textSecondary)
                }
                Spacer(minLength: 4)
                ring
            }
            HStack(spacing: 10) {
                Button { vm.cancelCountdown() } label: {
                    Text("Abbrechen")
                        .font(.system(.subheadline, design: .rounded).weight(.bold))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 10)
                        .background(Capsule().fill(Theme.surfaceHigh))
                }
                .buttonStyle(PressableStyle())
                Button { vm.playNext() } label: {
                    Text("Abspielen")
                        .font(.system(.subheadline, design: .rounded).weight(.bold))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 10)
                        .background(Capsule().fill(Theme.accentGradient))
                }
                .buttonStyle(PressableStyle())
            }
        }
        .foregroundStyle(.white)
        .padding(14)
        .frame(width: 330)
        .background(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(Theme.surface.opacity(0.96))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .strokeBorder(Theme.accent.opacity(0.6), lineWidth: 1)
        )
        .shadow(color: .black.opacity(0.5), radius: 14, y: 6)
    }

    private var nextTitle: String {
        guard let next = nextEpisode else { return "Nächste Folge" }
        return next.title.isEmpty ? next.code : "\(next.code) · \(next.title)"
    }

    private var thumbnail: some View {
        ZStack {
            CoverPlaceholder(title: vm.series.title)
            CachedImage(url: vm.series.coverURL)
        }
        .frame(width: 80, height: 50)
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
    }

    private var ring: some View {
        ZStack {
            Circle()
                .stroke(Color.white.opacity(0.15), lineWidth: 4)
            Circle()
                .trim(from: 0, to: CGFloat(fraction))
                .stroke(Theme.accentGradient, style: StrokeStyle(lineWidth: 4, lineCap: .round))
                .rotationEffect(.degrees(-90))
                .animation(.linear(duration: 1), value: seconds)
            Text("\(seconds)")
                .font(.system(.subheadline, design: .rounded).weight(.heavy))
                .monospacedDigit()
        }
        .frame(width: 44, height: 44)
    }
}
