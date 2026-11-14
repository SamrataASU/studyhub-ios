import AppIntents
import SwiftUI
import WidgetKit

@main
struct StudyHubWidgets: WidgetBundle {
    var body: some Widget {
        NextDeadlineWidget()
        DeadlineListWidget()
        LockScreenWidget()
    }
}

// MARK: - Data

struct DeadlineEntry: TimelineEntry {
    let date: Date
    let upcoming: [StudyItem]
    let weekDone: Int
    let weekTotal: Int
    let hasFeed: Bool
}

enum WidgetData {
    static func makeEntry(items: [StudyItem], now: Date = .now) -> DeadlineEntry {
        let state = SharedData.loadState()
        let isDone: (StudyItem) -> Bool = { state.marks[$0.id] ?? false }
        let deadlines = items.filter(\.tracksCompletion)
        let upcoming = deadlines.filter { !isDone($0) && $0.due >= now }.sorted { $0.due < $1.due }
        var weekDone = 0
        var weekTotal = 0
        if let week = StudyWeek.current(now) {
            let thisWeek = deadlines.filter { week.contains($0.due) }
            weekTotal = thisWeek.count
            weekDone = thisWeek.filter(isDone).count
        }
        return DeadlineEntry(date: now, upcoming: Array(upcoming.prefix(8)), weekDone: weekDone,
                             weekTotal: weekTotal, hasFeed: !(state.canvasFeed ?? "").isEmpty)
    }

    static func demo(_ title: String, _ course: String, hours: Double, kind: ItemKind) -> StudyItem {
        StudyItem(id: title, title: title, course: course, start: Date().addingTimeInterval(hours * 3600),
                  end: nil, isAllDay: false, kind: kind, source: .canvas, url: nil, notes: nil,
                  location: nil, tint: kind.color, eventIdentifier: nil)
    }

    static var sample: DeadlineEntry {
        DeadlineEntry(date: .now, upcoming: [
            demo("Factor Loadings", "FIN 525", hours: 7, kind: .assignment),
            demo("Midterm Exam", "FIN 555", hours: 50, kind: .exam),
            demo("Case Write-up", "WPC 502", hours: 76, kind: .assignment),
        ], weekDone: 2, weekTotal: 5, hasFeed: true)
    }
}

struct DeadlineProvider: TimelineProvider {
    func placeholder(in context: Context) -> DeadlineEntry { WidgetData.sample }

    func getSnapshot(in context: Context, completion: @escaping (DeadlineEntry) -> Void) {
        if context.isPreview {
            completion(WidgetData.sample)
        } else {
            completion(WidgetData.makeEntry(items: SharedData.cachedItems()))
        }
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<DeadlineEntry>) -> Void) {
        Task {
            let items = await SharedData.freshItems()
            let entry = WidgetData.makeEntry(items: items)
            completion(Timeline(entries: [entry], policy: .after(Date().addingTimeInterval(30 * 60))))
        }
    }
}

/// Runs when you tap ✓ on a widget: marks the deadline done (the app sees it too).
struct ToggleDoneIntent: AppIntent {
    static let title: LocalizedStringResource = "Mark deadline done"

    @Parameter(title: "Deadline")
    var itemID: String

    init() {}

    init(itemID: String) {
        self.itemID = itemID
    }

    func perform() async throws -> some IntentResult {
        var state = SharedData.loadState()
        state.marks[itemID] = !(state.marks[itemID] ?? false)
        SharedData.saveState(state)
        return .result()
    }
}

// MARK: - Widgets

struct NextDeadlineWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "NextDeadline", provider: DeadlineProvider()) { entry in
            NextDeadlineView(entry: entry)
                .containerBackground(for: .widget) { WidgetBackground() }
        }
        .configurationDisplayName("Next deadline")
        .description("Countdown to your next ASU deadline. Tap ✓ when it's done.")
        .supportedFamilies([.systemSmall])
    }
}

struct DeadlineListWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "DeadlineList", provider: DeadlineProvider()) { entry in
            DeadlineListView(entry: entry)
                .containerBackground(for: .widget) { WidgetBackground() }
        }
        .configurationDisplayName("Upcoming deadlines")
        .description("Your next ASU deadlines. Tap a circle to tick one off.")
        .supportedFamilies([.systemMedium, .systemLarge])
    }
}

struct LockScreenWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "LockScreen", provider: DeadlineProvider()) { entry in
            LockScreenView(entry: entry)
                .containerBackground(for: .widget) { Color.clear }
        }
        .configurationDisplayName("Deadline countdown")
        .description("Your next deadline on the Lock Screen.")
        .supportedFamilies([.accessoryRectangular, .accessoryCircular, .accessoryInline])
    }
}

// MARK: - Views

struct WidgetBackground: View {
    var body: some View {
        LinearGradient(colors: [Theme.bgTop, Theme.bgBottom], startPoint: .top, endPoint: .bottom)
    }
}

struct EmptyWidget: View {
    let hasFeed: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Image(systemName: hasFeed ? "checkmark.seal.fill" : "link")
                .font(.title3)
                .foregroundStyle(Theme.mint)
            Text(hasFeed ? "All caught up" : "Open StudyHub")
                .font(.headline)
                .foregroundStyle(Color.white)
            Text(hasFeed ? "No upcoming deadlines." : "Add your Canvas link to see deadlines.")
                .font(.caption2)
                .foregroundStyle(Color.white.opacity(0.7))
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
    }
}

struct NextDeadlineView: View {
    let entry: DeadlineEntry

    var body: some View {
        if let item = entry.upcoming.first {
            VStack(alignment: .leading, spacing: 4) {
                Label(item.kind.label, systemImage: item.kind.icon)
                    .font(.caption2.weight(.bold))
                    .foregroundStyle(item.kind.color)
                    .lineLimit(1)
                Text(item.title)
                    .font(.system(.subheadline, design: .rounded).weight(.bold))
                    .foregroundStyle(Color.white)
                    .lineLimit(3)
                Spacer(minLength: 0)
                Text(item.due, style: .relative)
                    .font(.system(.headline, design: .rounded).weight(.heavy))
                    .foregroundStyle(Color.white)
                    .lineLimit(1)
                    .minimumScaleFactor(0.6)
                HStack {
                    Text(item.course ?? item.due.formatted(.dateTime.weekday(.abbreviated).hour().minute()))
                        .font(.caption2)
                        .foregroundStyle(Color.white.opacity(0.7))
                        .lineLimit(1)
                    Spacer(minLength: 4)
                    Button(intent: ToggleDoneIntent(itemID: item.id)) {
                        Image(systemName: "checkmark.circle.fill")
                            .font(.title3)
                            .foregroundStyle(Theme.mint)
                    }
                    .buttonStyle(.plain)
                }
            }
        } else {
            EmptyWidget(hasFeed: entry.hasFeed)
        }
    }
}

struct DeadlineListView: View {
    @Environment(\.widgetFamily) private var family
    let entry: DeadlineEntry

    private var rows: Int { family == .systemLarge ? 6 : 3 }

    var body: some View {
        VStack(alignment: .leading, spacing: family == .systemLarge ? 10 : 6) {
            HStack {
                Text("DEADLINES")
                    .font(.caption.weight(.heavy))
                    .tracking(1.2)
                    .foregroundStyle(Theme.violet)
                Spacer()
                Text("\(entry.weekDone)/\(entry.weekTotal) done this week")
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(Color.white.opacity(0.7))
            }
            if entry.upcoming.isEmpty {
                EmptyWidget(hasFeed: entry.hasFeed)
            } else {
                ForEach(entry.upcoming.prefix(rows)) { item in
                    DeadlineRow(item: item)
                }
                Spacer(minLength: 0)
            }
        }
    }
}

struct DeadlineRow: View {
    let item: StudyItem

    var body: some View {
        HStack(spacing: 8) {
            Button(intent: ToggleDoneIntent(itemID: item.id)) {
                Image(systemName: "circle")
                    .font(.body.weight(.semibold))
                    .foregroundStyle(item.kind.color)
            }
            .buttonStyle(.plain)
            VStack(alignment: .leading, spacing: 1) {
                Text(item.title)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(Color.white)
                    .lineLimit(1)
                Text(item.course ?? item.kind.label)
                    .font(.caption2)
                    .foregroundStyle(Color.white.opacity(0.6))
                    .lineLimit(1)
            }
            Spacer(minLength: 4)
            Text(Fmt.short(item.due.timeIntervalSinceNow))
                .font(.caption2.weight(.bold).monospacedDigit())
                .foregroundStyle(badgeColor)
                .padding(.horizontal, 6)
                .padding(.vertical, 3)
                .background(badgeColor.opacity(0.18), in: Capsule())
        }
    }

    private var badgeColor: Color {
        let s = item.due.timeIntervalSinceNow
        if s < 86_400 { return Theme.amber }
        if s < 3 * 86_400 { return Theme.sky }
        return Color.white.opacity(0.7)
    }
}

struct LockScreenView: View {
    @Environment(\.widgetFamily) private var family
    let entry: DeadlineEntry

    private var dueThisWeek: Int {
        max(entry.weekTotal - entry.weekDone, 0)
    }

    var body: some View {
        switch family {
        case .accessoryCircular:
            Gauge(value: Double(entry.weekDone), in: 0...Double(max(entry.weekTotal, 1))) {
                Image(systemName: "graduationcap.fill")
            } currentValueLabel: {
                Text("\(dueThisWeek)")
            }
            .gaugeStyle(.accessoryCircular)
        case .accessoryInline:
            if let next = entry.upcoming.first {
                Text("\(next.title) · \(Fmt.short(next.due.timeIntervalSinceNow))")
            } else {
                Text("All caught up")
            }
        default:
            if let next = entry.upcoming.first {
                VStack(alignment: .leading, spacing: 1) {
                    Label("Next due", systemImage: "graduationcap.fill")
                        .font(.caption2.weight(.bold))
                    Text(next.title)
                        .font(.headline)
                        .lineLimit(1)
                    Text(next.due, style: .relative)
                        .font(.caption)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            } else {
                Text("All caught up 🎉").font(.headline)
            }
        }
    }
}
