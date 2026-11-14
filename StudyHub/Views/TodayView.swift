import SwiftUI

struct TodayView: View {
    @EnvironmentObject var store: StudyStore
    @AppStorage("userName") private var name = ""

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    header
                    if store.canvasFeed.isEmpty {
                        SetupCard()
                    }
                    if let next = store.nextDeadline {
                        NextUpCard(item: next)
                    } else {
                        allClearCard
                    }
                    statsRow
                    FocusCard()
                    section("Today", items: store.items(on: .now), empty: "Nothing scheduled today.", showDate: false)
                    section("Next 7 days", items: nextSevenDays, empty: "No deadlines this week. Get ahead!", showDate: true)
                    if !store.overdue.isEmpty {
                        section("Overdue", items: store.overdue, empty: "", showDate: true)
                    }
                    QuoteCard()
                }
                .pageColumn()
            }
            .scrollIndicators(.hidden)
            .background(AppBackground())
            .refreshable { await store.refresh() }
            .navigationTitle("Today")
            .inlineTitle()
            .toolbar {
                ToolbarItem(placement: .primaryAction) { SettingsButton() }
            }
        }
    }

    private var nextSevenDays: [StudyItem] {
        let limit = Date().adding(days: 7)
        return store.upcoming.filter { $0.due < limit && !Calendar.current.isDateInToday($0.start) }
    }

    private var dueSoonCount: Int {
        let limit: Date = Date().adding(days: 7)
        let open: [StudyItem] = store.upcoming
        return open.filter { $0.due < limit }.count
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(Date.now.formatted(.dateTime.weekday(.wide).month(.wide).day()).uppercased())
                .font(.caption.weight(.bold))
                .tracking(1.2)
                .foregroundStyle(Theme.violet)
            Text(name.isEmpty ? Fmt.greeting() : "\(Fmt.greeting()), \(name)")
                .font(.system(.largeTitle, design: .rounded).weight(.bold))
            SyncStatusLine()
        }
        .padding(.top, 4)
    }

    private var allClearCard: some View {
        GlassCard(padding: 20) {
            HStack(spacing: 14) {
                Image(systemName: "checkmark.seal.fill")
                    .font(.system(size: 36))
                    .foregroundStyle(Theme.mint.gradient)
                VStack(alignment: .leading, spacing: 4) {
                    Text("All caught up").font(.title3.bold())
                    Text("No upcoming deadlines. A great time to review notes or read ahead.")
                        .font(.subheadline).foregroundStyle(.secondary)
                }
            }
        }
    }

    private var statsRow: some View {
        let p = store.weekProgress
        let progress = p.total == 0 ? 0 : Double(p.done) / Double(p.total)
        let status: String = p.total == 0 ? "Free week" : (p.done == p.total ? "All done 🎉" : "\(p.total - p.done) to go")
        return HStack(spacing: 12) {
            GlassCard(padding: 14) {
                HStack(spacing: 12) {
                    ZStack {
                        ProgressRing(progress: progress, lineWidth: 8)
                        Text("\(p.done)/\(p.total)").font(.caption.weight(.bold)).monospacedDigit()
                    }
                    .frame(width: 56, height: 56)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("This week").font(.caption).foregroundStyle(.secondary)
                        Text(status).font(.headline).lineLimit(1).minimumScaleFactor(0.8)
                    }
                }
            }
            .frame(height: 86)
            StatTile(value: "\(dueSoonCount)", label: "Due in 7 days", color: Theme.amber)
            StatTile(value: "\(store.overdue.count)", label: "Overdue",
                     color: store.overdue.isEmpty ? Theme.mint : Theme.coral)
        }
    }

    @ViewBuilder
    private func section(_ title: String, items: [StudyItem], empty: String, showDate: Bool) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            SectionHeader(title: title, count: items.count)
            if items.isEmpty {
                Text(empty).font(.subheadline).foregroundStyle(.secondary).padding(.vertical, 4)
            } else {
                ForEach(items) { item in
                    ItemRow(item: item, showDate: showDate)
                }
            }
        }
    }
}

struct NextUpCard: View {
    @EnvironmentObject var store: StudyStore
    let item: StudyItem

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("NEXT DEADLINE")
                    .font(.caption.weight(.heavy))
                    .tracking(1.5)
                    .foregroundStyle(Color.white.opacity(0.85))
                Spacer()
                Label(item.kind.label, systemImage: item.kind.icon)
                    .font(.caption2.weight(.bold))
                    .padding(.horizontal, 8).padding(.vertical, 4)
                    .background(Color.white.opacity(0.2), in: Capsule())
            }
            Text(item.title)
                .font(.system(.title2, design: .rounded).weight(.bold))
                .lineLimit(3)
            if let course = item.course {
                Text(course).font(.subheadline).foregroundStyle(Color.white.opacity(0.8)).lineLimit(1)
            }
            TimelineView(.periodic(from: .now, by: 30)) { context in
                Text(Fmt.countdown(to: item.due, now: context.date))
                    .font(.system(size: 34, weight: .heavy, design: .rounded))
                    .monospacedDigit()
            }
            HStack {
                Text(item.due.formatted(.dateTime.weekday(.abbreviated).month(.abbreviated).day().hour().minute()))
                    .font(.footnote.weight(.medium))
                    .foregroundStyle(Color.white.opacity(0.85))
                Spacer()
                Button {
                    withAnimation(.snappy) { store.toggleDone(item) }
                } label: {
                    Label("Done", systemImage: "checkmark")
                        .font(.subheadline.weight(.bold))
                        .padding(.horizontal, 14).padding(.vertical, 8)
                        .background(Color.white.opacity(0.22), in: Capsule())
                }
                .buttonStyle(.plain)
            }
        }
        .foregroundStyle(Color.white)
        .padding(20)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            LinearGradient(colors: [item.kind.color.opacity(0.95), Theme.violet],
                           startPoint: .topLeading, endPoint: .bottomTrailing),
            in: RoundedRectangle(cornerRadius: 26, style: .continuous)
        )
        .shadow(color: Theme.violet.opacity(0.45), radius: 22, y: 10)
    }
}

struct SetupCard: View {
    @EnvironmentObject var store: StudyStore
    @State private var feed = ""

    var body: some View {
        GlassCard {
            VStack(alignment: .leading, spacing: 12) {
                Label("Connect your ASU Canvas", systemImage: "graduationcap.fill").font(.headline)
                if store.canvasFeed.isEmpty {
                    Text("Paste your ASU Canvas calendar link (Canvas → Calendar → “Calendar Feed”, bottom right).")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    HStack {
                        TextField("https://canvas.asu.edu/feeds/calendars/…", text: $feed)
                            .textFieldStyle(.roundedBorder)
                            .urlEntry()
                        Button("Save") { store.setCanvasFeed(feed) }
                            .buttonStyle(.borderedProminent)
                            .disabled(feed.trimmingCharacters(in: .whitespaces).isEmpty)
                    }
                }
            }
        }
    }
}

struct QuoteCard: View {
    static let lines = [
        "Small steps today, big wins in December.",
        "You don't need to feel ready. You just need to start.",
        "One focused hour beats three distracted ones.",
        "Future you is going to be so grateful for this.",
        "Progress, not perfection. Open the file and begin.",
        "Discipline is choosing what you want most over what you want now.",
        "Every deadline you beat is proof you can do hard things.",
        "Done is a feeling worth chasing. Go get it.",
        "Ten minutes of work is better than zero minutes of worry.",
        "The finance career you want is built one assignment at a time.",
        "Start before you're motivated. Motivation shows up later.",
        "Make today the day the list gets shorter.",
        "Your effort compounds, just like interest.",
        "Hard now, easy later. Easy now, hard later.",
    ]

    var body: some View {
        let day = Calendar.current.ordinality(of: .day, in: .year, for: .now) ?? 0
        GlassCard {
            HStack(alignment: .top, spacing: 12) {
                Image(systemName: "sparkles").font(.title3).foregroundStyle(Theme.amber)
                Text(Self.lines[day % Self.lines.count])
                    .font(.system(.callout, design: .serif).italic())
            }
        }
    }
}
