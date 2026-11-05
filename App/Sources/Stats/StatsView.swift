import SwiftUI
import Charts
import AniworldKit

enum StatsPalette {
    static let colors: [Color] = [
        Theme.accent,
        Theme.accentPink,
        Color(red: 0.98, green: 0.65, blue: 0.30),
        Color(red: 0.30, green: 0.78, blue: 0.95),
        Theme.success,
    ]

    static func color(at index: Int) -> Color {
        colors[index % colors.count]
    }
}

/// "Statistiken": hero card, numbers, charts and fun facts for a month, the year or everything.
struct StatsView: View {
    @Environment(WatchStatsStore.self) private var store
    @State private var period: StatsPeriod = StatsPeriod.month(containing: Date(), calendar: Calendar.current)
    @State private var recapPeriod: StatsPeriod?

    private var calendar: Calendar { Calendar.current }

    private var periodOptions: [StatsPeriod] {
        StatsPeriod.availableMonths(firstDate: store.firstSessionDate, now: Date(), calendar: calendar)
    }

    var body: some View {
        let stats: WatchStats = store.stats(for: period)
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                periodPicker
                StreakCard(streak: store.streak())
                if stats.hasData {
                    heroCard(stats)
                    tilesGrid(stats)
                    topSeriesCard(stats)
                    if !stats.topGenres.isEmpty { genresCard(stats) }
                    if !stats.languages.isEmpty { languagesCard(stats) }
                    rhythmCard(stats)
                    funFactsCard(stats)
                } else {
                    emptyCard
                }
            }
            .padding(.horizontal, Theme.screenPadding)
            .padding(.vertical, 12)
        }
        .background(AppBackground())
        .navigationTitle("Statistiken")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            if period.monthName != nil && stats.hasData {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        recapPeriod = period
                    } label: {
                        Label("Rückblick", systemImage: "sparkles")
                    }
                }
            }
        }
        .fullScreenCover(item: $recapPeriod) { (p: StatsPeriod) in
            RecapStoryView(period: p, stats: store.stats(for: p)) { recapPeriod = nil }
        }
    }

    // MARK: Picker

    private var periodPicker: some View {
        Menu {
            ForEach(periodOptions) { (option: StatsPeriod) in
                Button {
                    period = option
                } label: {
                    if option == period {
                        Label(option.title, systemImage: "checkmark")
                    } else {
                        Text(option.title)
                    }
                }
            }
            Divider()
            let thisYear = StatsPeriod.year(calendar.component(.year, from: Date()))
            Button {
                period = thisYear
            } label: {
                if period == thisYear {
                    Label("Dieses Jahr", systemImage: "checkmark")
                } else {
                    Text("Dieses Jahr")
                }
            }
            Button {
                period = .all
            } label: {
                if period == .all {
                    Label("Gesamt", systemImage: "checkmark")
                } else {
                    Text("Gesamt")
                }
            }
        } label: {
            HStack(spacing: 6) {
                Text(pickerTitle)
                Image(systemName: "chevron.down")
                    .font(.caption.weight(.bold))
            }
            .font(.system(.subheadline, design: .rounded).weight(.semibold))
            .foregroundStyle(.white)
            .chipBackground(selected: true)
        }
    }

    private var pickerTitle: String {
        if case .year = period { return "Dieses Jahr" }
        return period.title
    }

    // MARK: Cards

    private var emptyCard: some View {
        VStack(spacing: 10) {
            Image(systemName: "chart.bar.xaxis")
                .font(.system(size: 40))
                .foregroundStyle(Theme.accentGradient)
            Text("Noch keine Daten")
                .font(AppFont.sectionTitle)
                .foregroundStyle(.white)
            Text("Sobald du Folgen anschaust, erscheinen hier deine Statistiken. Sehr kurze Ausschnitte unter 30 Sekunden zählen nicht.")
                .font(.subheadline)
                .foregroundStyle(Theme.textSecondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(28)
        .background(RoundedRectangle(cornerRadius: Theme.cardRadius, style: .continuous).fill(Theme.surface))
    }

    private func heroCard(_ stats: WatchStats) -> some View {
        let hm = StatsFormat.hoursMinutes(stats.totalSeconds)
        return VStack(alignment: .leading, spacing: 8) {
            Text(period.title.uppercased())
                .font(AppFont.caption)
                .foregroundStyle(.white.opacity(0.8))
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                if hm.hours > 0 {
                    Text("\(hm.hours)").font(AppFont.display(54))
                    Text("Std").font(.system(.title3, design: .rounded).weight(.bold))
                }
                Text("\(hm.minutes)").font(AppFont.display(54))
                Text("Min").font(.system(.title3, design: .rounded).weight(.bold))
            }
            .foregroundStyle(.white)
            Text("Sehzeit")
                .font(.subheadline)
                .foregroundStyle(.white.opacity(0.85))
            if let change = stats.changeToPrevious {
                Label("\(StatsFormat.signedPercent(change)) zum Vorzeitraum",
                      systemImage: change >= 0 ? "arrow.up.right" : "arrow.down.right")
                    .font(.system(.footnote, design: .rounded).weight(.semibold))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 5)
                    .background(Capsule().fill(Color.white.opacity(0.2)))
                    .padding(.top, 4)
            }
            if let fun = stats.funComparison {
                Text(fun)
                    .font(.footnote)
                    .foregroundStyle(.white.opacity(0.9))
                    .padding(.top, 2)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(20)
        .background(
            RoundedRectangle(cornerRadius: 22, style: .continuous).fill(Theme.accentGradient)
        )
        .shadow(color: Theme.accent.opacity(0.4), radius: 16, y: 8)
    }

    private func tilesGrid(_ stats: WatchStats) -> some View {
        let columns: [GridItem] = [GridItem(.flexible(), spacing: 12), GridItem(.flexible(), spacing: 12)]
        return LazyVGrid(columns: columns, spacing: 12) {
            tile("Folgen", "\(stats.episodeCount)", icon: "play.rectangle.fill")
            tile("Serien", "\(stats.seriesCount)", icon: "rectangle.stack.fill")
            tile("Ø Verweildauer", StatsFormat.duration(stats.averageSessionSeconds), icon: "hourglass")
            tile("Folgen pro Tag", StatsFormat.decimal(stats.averageEpisodesPerActiveDay), icon: "calendar")
            tile("Aktive Tage", "\(stats.activeDays)", icon: "flame.fill")
            tile("Abschlussquote", StatsFormat.percent(stats.completionRate), icon: "checkmark.seal.fill")
        }
    }

    private func tile(_ title: String, _ value: String, icon: String) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Image(systemName: icon)
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(Theme.accentGradient)
            Text(value)
                .font(.system(.title2, design: .rounded).weight(.heavy))
                .foregroundStyle(.white)
                .lineLimit(1)
                .minimumScaleFactor(0.6)
            Text(title)
                .font(.footnote)
                .foregroundStyle(Theme.textSecondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14)
        .background(RoundedRectangle(cornerRadius: Theme.cardRadius, style: .continuous).fill(Theme.surface))
    }

    private func card<Content: View>(_ title: String, icon: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            Label(title, systemImage: icon)
                .font(AppFont.sectionTitle)
                .foregroundStyle(.white)
            content()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .background(RoundedRectangle(cornerRadius: Theme.cardRadius, style: .continuous).fill(Theme.surface))
    }

    private func topSeriesCard(_ stats: WatchStats) -> some View {
        card("Top-Serien", icon: "crown.fill") {
            VStack(spacing: 14) {
                ForEach(Array(stats.topSeries.enumerated()), id: \.offset) { pair in
                    let index: Int = pair.offset
                    let item: SeriesStat = pair.element
                    HStack(spacing: 12) {
                        Text("\(index + 1)")
                            .font(AppFont.display(20))
                            .foregroundStyle(Theme.accentGradient)
                            .frame(width: 22)
                        CoverImage(url: item.coverURL, title: item.title, cornerRadius: 8)
                            .frame(width: 44)
                        VStack(alignment: .leading, spacing: 5) {
                            Text(item.title)
                                .font(.system(.subheadline, design: .rounded).weight(.semibold))
                                .foregroundStyle(.white)
                                .lineLimit(1)
                            Text("\(StatsFormat.duration(item.seconds)) · \(StatsFormat.count(item.episodes, singular: "Folge", plural: "Folgen")) · \(StatsFormat.percent(item.share))")
                                .font(.caption)
                                .foregroundStyle(Theme.textSecondary)
                            ProgressBar(value: item.share, height: 4)
                        }
                    }
                }
            }
        }
    }

    private func genresCard(_ stats: WatchStats) -> some View {
        card("Lieblingsgenres", icon: "theatermasks.fill") {
            HStack(alignment: .center, spacing: 16) {
                Chart {
                    ForEach(Array(stats.topGenres.enumerated()), id: \.offset) { pair in
                        let index: Int = pair.offset
                        let item: ShareStat = pair.element
                        SectorMark(angle: .value("Zeit", item.seconds), innerRadius: .ratio(0.6), angularInset: 2)
                            .cornerRadius(4)
                            .foregroundStyle(StatsPalette.color(at: index))
                    }
                }
                .frame(width: 130, height: 130)
                VStack(alignment: .leading, spacing: 8) {
                    ForEach(Array(stats.topGenres.enumerated()), id: \.offset) { pair in
                        let index: Int = pair.offset
                        let item: ShareStat = pair.element
                        HStack(spacing: 8) {
                            Circle().fill(StatsPalette.color(at: index)).frame(width: 10, height: 10)
                            Text(item.name)
                                .font(.subheadline)
                                .foregroundStyle(.white)
                                .lineLimit(1)
                            Spacer(minLength: 4)
                            Text(StatsFormat.percent(item.share))
                                .font(.subheadline.weight(.semibold))
                                .foregroundStyle(Theme.textSecondary)
                        }
                    }
                }
            }
        }
    }

    private func languagesCard(_ stats: WatchStats) -> some View {
        card("Sprachen", icon: "globe") {
            VStack(spacing: 12) {
                ForEach(Array(stats.languages.enumerated()), id: \.offset) { pair in
                    let item: ShareStat = pair.element
                    VStack(alignment: .leading, spacing: 5) {
                        HStack {
                            Text(item.name)
                                .font(.subheadline.weight(.semibold))
                                .foregroundStyle(.white)
                            Spacer()
                            Text("\(StatsFormat.percent(item.share)) · \(StatsFormat.duration(item.seconds))")
                                .font(.caption)
                                .foregroundStyle(Theme.textSecondary)
                        }
                        ProgressBar(value: item.share, height: 6)
                    }
                }
            }
        }
    }

    private func rhythmCard(_ stats: WatchStats) -> some View {
        card("Wann du schaust", icon: "clock.fill") {
            VStack(alignment: .leading, spacing: 18) {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Wochentage")
                        .font(.footnote.weight(.semibold))
                        .foregroundStyle(Theme.textSecondary)
                    Chart {
                        ForEach(Array(WatchStats.weekdayShortNames.enumerated()), id: \.offset) { pair in
                            let index: Int = pair.offset
                            let name: String = pair.element
                            BarMark(x: .value("Tag", name), y: .value("Minuten", stats.weekdaySeconds[index] / 60))
                                .cornerRadius(4)
                                .foregroundStyle(index == stats.mostActiveWeekday
                                                 ? AnyShapeStyle(Theme.accentGradient)
                                                 : AnyShapeStyle(Theme.surfaceHigh))
                        }
                    }
                    .chartYAxis(.hidden)
                    .frame(height: 130)
                }
                VStack(alignment: .leading, spacing: 6) {
                    Text("Tageszeit")
                        .font(.footnote.weight(.semibold))
                        .foregroundStyle(Theme.textSecondary)
                    Chart {
                        ForEach(TimeOfDay.allCases, id: \.self) { (tod: TimeOfDay) in
                            BarMark(x: .value("Zeit", tod.title), y: .value("Minuten", stats.timeOfDaySeconds[tod.rawValue] / 60))
                                .cornerRadius(4)
                                .foregroundStyle(tod == stats.mostActiveTimeOfDay
                                                 ? AnyShapeStyle(Theme.accentGradient)
                                                 : AnyShapeStyle(Theme.surfaceHigh))
                        }
                    }
                    .chartYAxis(.hidden)
                    .frame(height: 130)
                }
            }
        }
    }

    private func funFactsCard(_ stats: WatchStats) -> some View {
        let facts: [(icon: String, text: String)] = funFacts(stats)
        return card("Fun Facts", icon: "sparkles") {
            VStack(alignment: .leading, spacing: 12) {
                ForEach(Array(facts.enumerated()), id: \.offset) { pair in
                    let fact: (icon: String, text: String) = pair.element
                    HStack(alignment: .top, spacing: 12) {
                        Image(systemName: fact.icon)
                            .foregroundStyle(Theme.accentGradient)
                            .frame(width: 24)
                        Text(fact.text)
                            .font(.subheadline)
                            .foregroundStyle(.white)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
            }
        }
    }

    private func funFacts(_ stats: WatchStats) -> [(icon: String, text: String)] {
        var facts: [(icon: String, text: String)] = []
        if let binge = stats.longestBinge, binge.episodes >= 2 {
            facts.append(("tv.fill", "Dein längster Binge: \(binge.episodes) Folgen am Stück (\(StatsFormat.duration(binge.seconds)))."))
        }
        if stats.longestStreakDays >= 2 {
            facts.append(("flame.fill", "Längste Serie: \(stats.longestStreakDays) Tage in Folge geschaut."))
        }
        if let day = stats.mostActiveWeekdayName, let tod = stats.mostActiveTimeOfDay {
            facts.append(("calendar", "Dein aktivster Tag ist \(day), meist schaust du \(tod.title.lowercased())."))
        }
        if stats.skippedSeconds >= 60 {
            facts.append(("forward.fill", "Durch Überspringen von Intros und Outros hast du \(StatsFormat.duration(stats.skippedSeconds)) gespart."))
        }
        if stats.offlineShare > 0.01 {
            facts.append(("arrow.down.circle.fill", "\(StatsFormat.percent(stats.offlineShare)) deiner Sehzeit kamen aus Downloads."))
        }
        if stats.newSeriesCount > 0 {
            let word = stats.newSeriesCount == 1 ? "neue Serie" : "neue Serien"
            facts.append(("sparkle", "Du hast \(stats.newSeriesCount) \(word) angefangen."))
        }
        if let fun = stats.funComparison { facts.append(("film.fill", fun)) }
        return facts
    }
}

#Preview("Statistiken") {
    NavigationStack { StatsView() }.previewEnvironment()
}
