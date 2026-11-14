import SwiftUI

enum ItemKind: String, CaseIterable, Identifiable, Codable {
    case exam, assignment, classEvent, personal

    var id: String { rawValue }

    var label: String {
        switch self {
        case .exam: return "Exam"
        case .assignment: return "Assignment"
        case .classEvent: return "Class / Event"
        case .personal: return "Personal"
        }
    }

    var icon: String {
        switch self {
        case .exam: return "flame.fill"
        case .assignment: return "doc.text.fill"
        case .classEvent: return "book.closed.fill"
        case .personal: return "person.fill"
        }
    }

    var color: Color {
        switch self {
        case .exam: return Theme.coral
        case .assignment: return Theme.amber
        case .classEvent: return Theme.sky
        case .personal: return Theme.mint
        }
    }

    /// Guesses what an item is from its title and link.
    static func classify(title: String, url: URL?, fromCanvas: Bool) -> ItemKind {
        let t = title.lowercased()
        if t.range(of: #"\b(exam|midterm|quiz|test|final exam)\b"#, options: .regularExpression) != nil {
            return .exam
        }
        if let u = url?.absoluteString.lowercased() {
            if u.contains("/quizzes/") { return .exam }
            if u.contains("assignment") || u.contains("/discussion_topics/") { return .assignment }
        }
        let homework = #"\b(assignment|homework|hw|due|submit|submission|project|paper|essay|case|problem set|pset|report|presentation|discussion|lab)\b"#
        if t.range(of: homework, options: .regularExpression) != nil { return .assignment }
        return fromCanvas ? .classEvent : .personal
    }
}

enum ItemSource: String, Codable {
    case canvas, appleCalendar, manual

    var label: String {
        switch self {
        case .canvas: return "ASU Canvas"
        case .appleCalendar: return "Apple Calendar"
        case .manual: return "Added by you"
        }
    }

    var icon: String {
        switch self {
        case .canvas: return "graduationcap.fill"
        case .appleCalendar: return "calendar"
        case .manual: return "pencil"
        }
    }
}

struct StudyItem: Identifiable, Hashable, Sendable {
    let id: String
    var title: String
    var course: String?
    var start: Date
    var end: Date?
    var isAllDay: Bool
    var kind: ItemKind
    var source: ItemSource
    var url: URL?
    var notes: String?
    var location: String?
    var tint: Color
    var eventIdentifier: String?

    var isDeadline: Bool { kind == .exam || kind == .assignment }
    /// Items that get a ✓ checkbox.
    var tracksCompletion: Bool { isDeadline || source == .manual }

    /// The moment something is actually due (all-day items are due at the end of the day).
    var due: Date {
        guard isAllDay else { return start }
        return start.startOfDay.adding(days: 1).addingTimeInterval(-60)
    }
}

extension Date {
    var startOfDay: Date { Calendar.current.startOfDay(for: self) }
    var startOfMonth: Date {
        Calendar.current.date(from: Calendar.current.dateComponents([.year, .month], from: self)) ?? self
    }
    func adding(days: Int) -> Date {
        Calendar.current.date(byAdding: .day, value: days, to: self) ?? self
    }
}

enum Fmt {
    static func dayHeader(_ d: Date) -> String {
        let c = Calendar.current
        if c.isDateInToday(d) { return "Today" }
        if c.isDateInTomorrow(d) { return "Tomorrow" }
        if c.isDateInYesterday(d) { return "Yesterday" }
        return d.formatted(.dateTime.weekday(.wide).month(.abbreviated).day())
    }

    static func time(_ item: StudyItem) -> String {
        item.isAllDay ? "All day" : item.start.formatted(date: .omitted, time: .shortened)
    }

    static func countdown(to date: Date, now: Date = .now) -> String {
        let s = Int(date.timeIntervalSince(now))
        if s <= 0 {
            let a = -s
            if a < 3600 { return "Just passed" }
            if a < 86400 { return "\(a / 3600)h overdue" }
            return "\(a / 86400)d overdue"
        }
        let d = s / 86400, h = (s % 86400) / 3600, m = (s % 3600) / 60
        if d > 0 { return "\(d)d \(h)h left" }
        if h > 0 { return "\(h)h \(m)m left" }
        return "\(m)m left"
    }

    static func short(_ seconds: TimeInterval) -> String {
        if seconds < 0 { return "Overdue" }
        if seconds < 3600 { return "\(Int(seconds / 60))m" }
        if seconds < 86400 { return "\(Int(seconds / 3600))h" }
        return "\(Int(seconds / 86400))d"
    }

    static func greeting(_ date: Date = .now) -> String {
        switch Calendar.current.component(.hour, from: date) {
        case 5..<12: return "Good morning"
        case 12..<17: return "Good afternoon"
        default: return "Good evening"
        }
    }
}

/// Weeks always run Monday 12:00 AM → Sunday 11:59 PM.
enum StudyWeek {
    static var calendar: Calendar {
        var c = Calendar.current
        c.firstWeekday = 2   // Monday
        return c
    }

    /// This Monday–Sunday.
    static func current(_ now: Date = .now) -> DateInterval? {
        calendar.dateInterval(of: .weekOfYear, for: now)
    }
}
