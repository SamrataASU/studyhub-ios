import SwiftUI
import WidgetKit

/// The app's brain: downloads your ASU Canvas calendar and keeps track of what you've finished.
@MainActor
final class StudyStore: ObservableObject {
    @Published private(set) var items: [StudyItem] = []
    @Published private(set) var isRefreshing = false
    @Published private(set) var lastSynced: Date?
    @Published private(set) var canvasError: String?
    @Published private(set) var saved = SavedState()

    @Published var notificationsOn: Bool {
        didSet {
            UserDefaults.standard.set(notificationsOn, forKey: Keys.notifications)
            let on = notificationsOn
            Task {
                if on { await NotificationService.requestPermission() }
                await self.rescheduleNotifications()
            }
        }
    }

    private enum Keys {
        static let notifications = "notificationsOn"
    }

    init() {
        notificationsOn = UserDefaults.standard.object(forKey: Keys.notifications) as? Bool ?? true
        saved = SharedData.loadState()
        if let text = try? String(contentsOf: CanvasService.cacheURL, encoding: .utf8) {
            items = Self.inRange(CanvasService.items(fromICS: text))
        }
    }

    // MARK: - Public info

    var canvasFeed: String { saved.canvasFeed ?? "" }
    var canvasCount: Int { items.count }

    var deadlines: [StudyItem] { items.filter(\.tracksCompletion) }

    var upcoming: [StudyItem] {
        let now = Date()
        return deadlines.filter { !isDone($0) && $0.due >= now }.sorted { $0.due < $1.due }
    }

    var overdue: [StudyItem] {
        let now = Date(), cutoff = Date().adding(days: -21)
        return deadlines.filter { !isDone($0) && $0.due < now && $0.due > cutoff }
    }

    var nextDeadline: StudyItem? { upcoming.first }

    func items(on day: Date) -> [StudyItem] {
        items.filter { Calendar.current.isDate($0.start, inSameDayAs: day) }
    }

    var weekProgress: (done: Int, total: Int) {
        guard let week = StudyWeek.current() else { return (0, 0) }
        let thisWeek = deadlines.filter { week.contains($0.due) }
        return (thisWeek.filter { isDone($0) }.count, thisWeek.count)
    }

    func isDone(_ item: StudyItem) -> Bool { saved.marks[item.id] ?? false }

    // MARK: - Actions

    func toggleDone(_ item: StudyItem) {
        saved.marks[item.id] = !isDone(item)
        save()
        Task { await rescheduleNotifications() }
    }

    func setCanvasFeed(_ raw: String) {
        saved.canvasFeed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        save()
        Task { await refresh() }
    }

    /// Downloads the Canvas calendar. Runs on launch, when the app comes back, every 15 min,
    /// and when you pull down to refresh.
    func refresh() async {
        guard !isRefreshing else { return }
        isRefreshing = true
        defer { isRefreshing = false }

        // Pick up anything you ticked off from a widget.
        let latest = SharedData.loadState()
        saved.marks = latest.marks

        if let feed = saved.canvasFeed, !feed.isEmpty {
            do {
                // Run the download on its own so leaving a screen or pulling to refresh can't cut it off.
                let text = try await Task { try await CanvasService.download(feed: feed) }.value
                items = Self.inRange(CanvasService.items(fromICS: text))
                try? text.write(to: CanvasService.cacheURL, atomically: true, encoding: .utf8)
                canvasError = nil
            } catch {
                // A stopped download isn't a real problem: keep the deadlines we already have.
                if !Self.isCancellation(error) {
                    canvasError = error.localizedDescription
                }
            }
        } else {
            items = []
            canvasError = nil
        }

        lastSynced = .now
        WidgetCenter.shared.reloadAllTimelines()
        await rescheduleNotifications()
    }

    func rescheduleNotifications() async {
        guard notificationsOn else {
            await NotificationService.clearDeadlines()
            return
        }
        await NotificationService.scheduleDeadlines(items.filter { $0.tracksCompletion && !isDone($0) })
    }

    // MARK: - Helpers

    private static func isCancellation(_ error: Error) -> Bool {
        if error is CancellationError { return true }
        if let urlError = error as? URLError, urlError.code == .cancelled { return true }
        return (error as NSError).code == NSURLErrorCancelled
    }

    private static func inRange(_ list: [StudyItem]) -> [StudyItem] {
        let from = Date().startOfDay.adding(days: -45)
        let to = Date().startOfDay.adding(days: 200)
        return list.filter { $0.start >= from && $0.start <= to }.sorted { $0.start < $1.start }
    }

    private func save() {
        SharedData.saveState(saved)
        WidgetCenter.shared.reloadAllTimelines()
    }
}
