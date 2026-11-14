import Foundation

/// Storage shared by the app and its widgets (through an App Group on this iPhone only).
enum AppPaths {
    static let groupID = "group.com.samratdas.studyhub"

    /// Where the app used to keep its data before widgets existed.
    static var legacy: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("StudyHub", isDirectory: true)
    }

    static var support: URL {
        let base = FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: groupID) ?? legacy
        try? FileManager.default.createDirectory(at: base, withIntermediateDirectories: true)
        return base
    }
}

/// Saved only on this iPhone: your ✓ marks and your Canvas link.
struct SavedState: Codable {
    var marks: [String: Bool] = [:]
    var canvasFeed: String?
}

enum SharedData {
    static var stateURL: URL { AppPaths.support.appendingPathComponent("saved-state.json") }

    static func loadState() -> SavedState {
        if let data = try? Data(contentsOf: stateURL),
           let state = try? JSONDecoder().decode(SavedState.self, from: data) {
            return state
        }
        // Carry over data from earlier versions of the app.
        let oldNew = AppPaths.legacy.appendingPathComponent("saved-state.json")
        if let data = try? Data(contentsOf: oldNew),
           let state = try? JSONDecoder().decode(SavedState.self, from: data) {
            saveState(state)
            return state
        }
        var state = SavedState()
        let oldest = AppPaths.legacy.appendingPathComponent("sync-state.json")
        if let data = try? Data(contentsOf: oldest),
           let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
            state.canvasFeed = json["canvasFeed"] as? String
        }
        return state
    }

    static func saveState(_ state: SavedState) {
        if let data = try? JSONEncoder().encode(state) {
            try? data.write(to: stateURL, options: .atomic)
        }
    }

    /// Canvas items from the last download (refreshed by the app and the widget).
    static func cachedItems() -> [StudyItem] {
        guard let text = try? String(contentsOf: CanvasService.cacheURL, encoding: .utf8) else { return [] }
        return CanvasService.items(fromICS: text)
    }

    /// Downloads a fresh copy of the Canvas calendar if a link is saved; falls back to the cache.
    static func freshItems() async -> [StudyItem] {
        guard let feed = loadState().canvasFeed, !feed.isEmpty,
              let text = try? await CanvasService.download(feed: feed) else {
            return cachedItems()
        }
        try? text.write(to: CanvasService.cacheURL, atomically: true, encoding: .utf8)
        return CanvasService.items(fromICS: text)
    }
}
