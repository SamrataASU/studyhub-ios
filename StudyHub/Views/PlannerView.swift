import SwiftUI

struct PlannerView: View {
    @EnvironmentObject var store: StudyStore
    @State private var month = Date().startOfMonth
    @State private var selected = Date().startOfDay

    private let cal = StudyWeek.calendar

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    GlassCard { monthGrid }
                    VStack(alignment: .leading, spacing: 10) {
                        SectionHeader(title: Fmt.dayHeader(selected), count: dayItems.count)
                        if dayItems.isEmpty {
                            Text("Nothing on this day.").font(.subheadline).foregroundStyle(.secondary)
                        }
                        ForEach(dayItems) { item in
                            ItemRow(item: item)
                        }
                    }
                }
                .padding(.top, 8)
                .pageColumn()
            }
            .scrollIndicators(.hidden)
            .background(AppBackground())
            .refreshable { await store.refresh() }
            .navigationTitle("Calendar")
            .inlineTitle()
            .toolbar {
                ToolbarItemGroup(placement: .primaryAction) {
                    Button("Today") {
                        withAnimation(.snappy) {
                            month = Date().startOfMonth
                            selected = Date().startOfDay
                        }
                    }
                    SettingsButton()
                }
            }
        }
    }

    private var dayItems: [StudyItem] { store.items(on: selected) }

    private var monthGrid: some View {
        let symbols = weekdaySymbols
        let days = gridDays
        return VStack(spacing: 12) {
            HStack {
                Text(month.formatted(.dateTime.month(.wide).year()))
                    .font(.system(.title3, design: .rounded).weight(.bold))
                Spacer()
                Button { shift(-1) } label: { Image(systemName: "chevron.left") }
                    .buttonStyle(.bordered).buttonBorderShape(.circle)
                Button { shift(1) } label: { Image(systemName: "chevron.right") }
                    .buttonStyle(.bordered).buttonBorderShape(.circle)
            }
            HStack(spacing: 4) {
                ForEach(symbols.indices, id: \.self) { i in
                    Text(symbols[i])
                        .font(.caption2.weight(.bold))
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity)
                }
            }
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 4), count: 7), spacing: 6) {
                ForEach(days.indices, id: \.self) { i in
                    if let day = days[i] {
                        DayCell(day: day,
                                isSelected: cal.isDate(day, inSameDayAs: selected),
                                items: store.items(on: day))
                            .onTapGesture {
                                withAnimation(.snappy) { selected = day }
                            }
                    } else {
                        Color.clear.frame(height: 46)
                    }
                }
            }
        }
    }

    private var weekdaySymbols: [String] {
        let s = cal.veryShortWeekdaySymbols
        let first = cal.firstWeekday - 1
        return Array(s[first...] + s[..<first])
    }

    private var gridDays: [Date?] {
        guard let range = cal.range(of: .day, in: .month, for: month) else { return [] }
        let firstWeekday = cal.component(.weekday, from: month)
        let leading = (firstWeekday - cal.firstWeekday + 7) % 7
        let blanks = [Date?](repeating: nil, count: leading)
        let dates: [Date?] = range.map { cal.date(byAdding: .day, value: $0 - 1, to: month) }
        return blanks + dates
    }

    private func shift(_ months: Int) {
        withAnimation(.snappy) {
            month = cal.date(byAdding: .month, value: months, to: month) ?? month
        }
    }
}

struct DayCell: View {
    let day: Date
    let isSelected: Bool
    let items: [StudyItem]

    var body: some View {
        let isToday = Calendar.current.isDateInToday(day)
        VStack(spacing: 4) {
            Text("\(Calendar.current.component(.day, from: day))")
                .font(.system(.callout, design: .rounded).weight(isToday || isSelected ? .bold : .regular))
                .foregroundStyle(isSelected ? Color.white : (isToday ? Theme.violet : Color.primary))
            HStack(spacing: 3) {
                ForEach(kinds.prefix(3), id: \.self) { k in
                    Circle().fill(k.color).frame(width: 5, height: 5)
                }
            }
            .frame(height: 5)
        }
        .frame(maxWidth: .infinity, minHeight: 46)
        .background {
            if isSelected {
                RoundedRectangle(cornerRadius: 12, style: .continuous).fill(Theme.violet.gradient)
            } else if isToday {
                RoundedRectangle(cornerRadius: 12, style: .continuous).strokeBorder(Theme.violet.opacity(0.6))
            }
        }
        .contentShape(Rectangle())
    }

    private var kinds: [ItemKind] {
        var seen: [ItemKind] = []
        for item in items where !seen.contains(item.kind) { seen.append(item.kind) }
        return seen
    }
}
