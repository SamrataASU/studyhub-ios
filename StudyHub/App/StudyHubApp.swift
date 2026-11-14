import SwiftUI

@main
struct StudyHubApp: App {
    @StateObject private var store = StudyStore()
    @StateObject private var focus = FocusTimer()

    var body: some Scene {
        WindowGroup {
            RootView()
                .environmentObject(store)
                .environmentObject(focus)
                .preferredColorScheme(.dark)
                .tint(Theme.violet)
            #if os(macOS)
                .frame(minWidth: 900, minHeight: 640)
            #endif
        }
    }
}

struct RootView: View {
    @EnvironmentObject var store: StudyStore
    @EnvironmentObject var focus: FocusTimer
    @Environment(\.scenePhase) private var scenePhase

    var body: some View {
        TabView {
            TodayView()
                .tabItem { Label("Today", systemImage: "sun.max.fill") }
            PlannerView()
                .tabItem { Label("Calendar", systemImage: "calendar") }
            TasksView()
                .tabItem { Label("Deadlines", systemImage: "checklist") }
            NewsView()
                .tabItem { Label("News", systemImage: "newspaper.fill") }
        }
        .task {
            if store.notificationsOn { await NotificationService.requestPermission() }
            NotificationService.scheduleDailyNews(enabled: UserDefaults.standard.object(forKey: "dailyNews") as? Bool ?? true)
            await store.refresh()
        }
        .task {
            // Keep everything fresh while the app is open (every 15 minutes).
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(900))
                await store.refresh()
            }
        }
        .fullScreenCover(isPresented: $focus.isPresented) {
            FocusScreen().environmentObject(focus)
        }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active { Task { await store.refresh() } }
        }
    }
}
