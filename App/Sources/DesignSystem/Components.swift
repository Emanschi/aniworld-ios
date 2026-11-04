import SwiftUI
import AniworldKit

/// Loading state of a screen section.
enum LoadPhase {
    case loading
    case loaded
    case failed(Error)

    var isLoading: Bool {
        if case .loading = self { return true }
        return false
    }
}

// MARK: Progress

struct ProgressBar: View {
    var value: Double
    var height: CGFloat = 4

    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                Capsule().fill(Color.white.opacity(0.22))
                Capsule()
                    .fill(Theme.accentGradient)
                    .frame(width: max(geo.size.width * CGFloat(min(max(value, 0), 1)), value > 0 ? height : 0))
            }
        }
        .frame(height: height)
    }
}

// MARK: Section header

struct SectionHeader: View {
    let title: String
    var subtitle: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title)
                .font(AppFont.sectionTitle)
                .foregroundStyle(.white)
            if let subtitle {
                Text(subtitle)
                    .font(.footnote)
                    .foregroundStyle(Theme.textSecondary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, Theme.screenPadding)
    }
}

// MARK: Errors

struct ErrorInfo {
    let icon: String
    let title: String
    let message: String

    init(_ error: Error) {
        if let aniworld = error as? AniworldError {
            switch aniworld {
            case .cloudflareChallenge:
                icon = "shield.lefthalf.filled"
                title = "Cloudflare-Prüfung"
                message = "aniworld.to verlangt gerade eine Sicherheitsprüfung. Versuche es in ein paar Minuten erneut oder wechsle das Netzwerk."
            case .http(let status, _):
                icon = "exclamationmark.triangle"
                title = "Serverfehler"
                message = "aniworld.to hat mit Fehler \(status) geantwortet. Bitte versuche es später erneut."
            case .parsing:
                icon = "doc.questionmark"
                title = "Unerwartete Antwort"
                message = "Die Seite konnte nicht gelesen werden. Möglicherweise hat aniworld.to sein Layout geändert."
            case .noPlayableStream:
                icon = "play.slash"
                title = "Kein Stream verfügbar"
                message = "Für diese Folge wurde kein abspielbarer Stream gefunden."
            case .cancelled:
                icon = "xmark.circle"
                title = "Abgebrochen"
                message = "Der Vorgang wurde abgebrochen."
            }
        } else if let urlError = error as? URLError {
            switch urlError.code {
            case .notConnectedToInternet, .networkConnectionLost, .dataNotAllowed:
                icon = "wifi.slash"
                title = "Keine Verbindung"
                message = "Du bist offenbar offline. Prüfe deine Internetverbindung und versuche es erneut."
            case .timedOut:
                icon = "clock.badge.exclamationmark"
                title = "Zeitüberschreitung"
                message = "Der Server antwortet nicht rechtzeitig. Bitte versuche es erneut."
            default:
                icon = "wifi.exclamationmark"
                title = "Netzwerkfehler"
                message = "Die Verbindung zu aniworld.to ist fehlgeschlagen. Bitte versuche es erneut."
            }
        } else {
            icon = "exclamationmark.triangle"
            title = "Etwas ist schiefgelaufen"
            message = "Bitte versuche es erneut."
        }
    }
}

struct ErrorStateView: View {
    let error: Error
    var retry: (() -> Void)?

    var body: some View {
        let info = ErrorInfo(error)
        VStack(spacing: 14) {
            Image(systemName: info.icon)
                .font(.system(size: 30, weight: .semibold))
                .foregroundStyle(Theme.accentGradient)
                .frame(width: 72, height: 72)
                .background(Circle().fill(Theme.surfaceHigh))
            Text(info.title)
                .font(AppFont.title)
                .foregroundStyle(.white)
            Text(info.message)
                .font(.subheadline)
                .foregroundStyle(Theme.textSecondary)
                .multilineTextAlignment(.center)
            if let retry {
                Button(action: retry) {
                    Label("Erneut versuchen", systemImage: "arrow.clockwise")
                }
                .buttonStyle(AccentButtonStyle())
                .padding(.top, 4)
            }
        }
        .padding(.horizontal, 32)
        .padding(.vertical, 40)
        .frame(maxWidth: .infinity)
    }
}

// MARK: Shimmer & skeletons

struct ShimmerModifier: ViewModifier {
    @State private var phase: CGFloat = -0.6

    func body(content: Content) -> some View {
        content
            .overlay {
                GeometryReader { geo in
                    LinearGradient(
                        colors: [.clear, Color.white.opacity(0.14), .clear],
                        startPoint: .leading, endPoint: .trailing
                    )
                    .frame(width: geo.size.width * 0.6)
                    .offset(x: phase * geo.size.width)
                }
                .allowsHitTesting(false)
            }
            .clipped()
            .onAppear {
                withAnimation(.linear(duration: 1.3).repeatForever(autoreverses: false)) {
                    phase = 1.0
                }
            }
    }
}

extension View {
    func shimmer() -> some View { modifier(ShimmerModifier()) }
}

struct SkeletonBox: View {
    var cornerRadius: CGFloat = Theme.cardRadius

    var body: some View {
        RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
            .fill(Color.white.opacity(0.07))
            .shimmer()
    }
}

/// Skeleton for a horizontal poster row.
struct PosterRowSkeleton: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            SkeletonBox(cornerRadius: 6)
                .frame(width: 140, height: 18)
                .padding(.horizontal, Theme.screenPadding)
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 14) {
                    ForEach(0..<5, id: \.self) { _ in
                        VStack(alignment: .leading, spacing: 8) {
                            SkeletonBox().frame(width: 130, height: 195)
                            SkeletonBox(cornerRadius: 4).frame(width: 100, height: 10)
                        }
                    }
                }
                .padding(.horizontal, Theme.screenPadding)
            }
            .disabled(true)
        }
    }
}

// MARK: Styles

struct AccentButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(.headline, design: .rounded))
            .foregroundStyle(.white)
            .padding(.horizontal, 22)
            .padding(.vertical, 13)
            .background(Capsule().fill(Theme.accentGradient))
            .shadow(color: Theme.accent.opacity(0.45), radius: 12, y: 6)
            .scaleEffect(configuration.isPressed ? 0.97 : 1)
            .animation(.easeOut(duration: 0.15), value: configuration.isPressed)
    }
}

struct PressableStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.96 : 1)
            .opacity(configuration.isPressed ? 0.9 : 1)
            .animation(.easeOut(duration: 0.15), value: configuration.isPressed)
    }
}

extension View {
    func cardShadow() -> some View {
        shadow(color: .black.opacity(0.45), radius: 10, x: 0, y: 6)
    }

    func chipBackground(selected: Bool = false) -> some View {
        self
            .padding(.horizontal, 14)
            .padding(.vertical, 8)
            .background(
                Capsule().fill(selected ? AnyShapeStyle(Theme.accentGradient) : AnyShapeStyle(Theme.surfaceHigh))
            )
    }
}

// MARK: Flow layout (wrapping chips)

struct FlowLayout: Layout {
    var spacing: CGFloat = 8

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let maxWidth = proposal.width ?? .infinity
        var x: CGFloat = 0
        var y: CGFloat = 0
        var rowHeight: CGFloat = 0
        var usedWidth: CGFloat = 0
        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if x > 0 && x + size.width > maxWidth {
                x = 0
                y += rowHeight + spacing
                rowHeight = 0
            }
            x += size.width + spacing
            rowHeight = max(rowHeight, size.height)
            usedWidth = max(usedWidth, x - spacing)
        }
        return CGSize(width: usedWidth, height: y + rowHeight)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var x = bounds.minX
        var y = bounds.minY
        var rowHeight: CGFloat = 0
        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if x > bounds.minX && x + size.width > bounds.maxX {
                x = bounds.minX
                y += rowHeight + spacing
                rowHeight = 0
            }
            subview.place(at: CGPoint(x: x, y: y), anchor: .topLeading, proposal: ProposedViewSize(size))
            x += size.width + spacing
            rowHeight = max(rowHeight, size.height)
        }
    }
}
