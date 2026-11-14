import SwiftUI

struct TasksView: View {
    enum Filter: String, CaseIterable, Identifiable {
        case upcoming = "Upcoming", overdue = "Overdue", done = "Done", all = "All"
        var id: String { rawValue }
    }

    struct DayGroup {
        let day: Date
        let items: [StudyItem]
    }

    @EnvironmentObject var store: StudyStore
    @State private var filter: Filter = .upcoming
    @State private var kindFilter: ItemKind?
    @State private var search = ""

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    Picker("Show", selection: $filter) {
                        ForEach(Filter.allCases) { Text($0.rawValue).tag($0) }
                    }
                    .pickerStyle(.segmented)
                    .labelsHidden()

                    kindChips

                    let groups = self.groups
                    if groups.isEmpty {
                        EmptyState(icon: emptyIcon, title: emptyTitle, message: emptyMessage)
                    }
                    ForEach(groups, id: \.day) { group in
                        VStack(alignment: .leading, spacing: 8) {
                            SectionHeader(title: Fmt.dayHeader(group.day), count: group.items.count)
                            ForEach(group.items) { item in
                                ItemRow(item: item)
                            }
                        }
                    }
                }
                .padding(.top, 8)
                .pageColumn()
            }
            .scrollIndicators(.hidden)
            .background(AppBackground())
            .searchable(text: $search, prompt: "Search deadlines or courses")
            .refreshable { await store.refresh() }
            .navigationTitle("Deadlines")
            .inlineTitle()
            .toolbar {
                ToolbarItem(placement: .primaryAction) { SettingsButton() }
            }
        }
    }

    private var kindChips: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                chip("All", icon: "square.grid.2x2.fill", color: Theme.violet, selected: kindFilter == nil) {
                    kindFilter = nil
                }
                ForEach(ItemKind.allCases) { k in
                    chip(k.label, icon: k.icon, color: k.color, selected: kindFilter == k) {
                        kindFilter = (kindFilter == k) ? nil : k
                    }
                }
            }
        }
    }

    private func chip(_ text: String, icon: String, color: Color, selected: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Label(text, systemImage: icon)
                .font(.caption.weight(.semibold))
                .padding(.horizontal, 12)
                .padding(.vertical, 7)
                .foregroundStyle(selected ? Color.white : color)
                .background(selected ? color.opacity(0.85) : color.opacity(0.14), in: Capsule())
        }
        .buttonStyle(.plain)
    }

    private var filtered: [StudyItem] {
        let now = Date()
        var list: [StudyItem]
        switch filter {
        case .upcoming: list = store.deadlines.filter { !store.isDone($0) && $0.due >= now }
        case .overdue: list = store.overdue
        case .done: list = store.deadlines.filter { store.isDone($0) }
        case .all: list = store.deadlines
        }
        if let k = kindFilter { list = list.filter { $0.kind == k } }
        let q = search.trimmingCharacters(in: .whitespaces)
        if !q.isEmpty {
            list = list.filter {
                $0.title.localizedCaseInsensitiveContains(q) || ($0.course ?? "").localizedCaseInsensitiveContains(q)
            }
        }
        return list
    }

    private var groups: [DayGroup] {
        let dict = Dictionary(grouping: filtered) { $0.start.startOfDay }
        var keys = dict.keys.sorted()
        if filter == .done { keys.reverse() }
        return keys.map { DayGroup(day: $0, items: (dict[$0] ?? []).sorted { $0.start < $1.start }) }
    }

    private var emptyIcon: String {
        filter == .done ? "tray" : "party.popper.fill"
    }

    private var emptyTitle: String {
        switch filter {
        case .upcoming: return "Nothing coming up"
        case .overdue: return "Nothing overdue"
        case .done: return "Nothing checked off yet"
        case .all: return "No deadlines yet"
        }
    }

    private var emptyMessage: String {
        store.canvasFeed.isEmpty
            ? "Add your Canvas link on the Today tab to bring in your deadlines."
            : "Enjoy the free time!"
    }
}
