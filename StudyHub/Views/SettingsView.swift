import SwiftUI

struct SettingsView: View {
    @EnvironmentObject var store: StudyStore
    @AppStorage("userName") private var name = ""
    @State private var feedDraft = ""
    @AppStorage("dailyNews") private var dailyNews = true
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            Form {
                Section("You") {
                    TextField("Your name", text: $name)
                }

                Section {
                    TextField("Canvas calendar feed link", text: $feedDraft)
                        .urlEntry()
                    Button("Save and sync") { store.setCanvasFeed(feedDraft) }
                        .disabled(feedDraft.trimmingCharacters(in: .whitespacesAndNewlines) == store.canvasFeed)
                    if let e = store.canvasError {
                        Label(e, systemImage: "exclamationmark.triangle")
                            .font(.footnote)
                            .foregroundStyle(Theme.amber)
                    } else if !store.canvasFeed.isEmpty {
                        Label("\(store.canvasCount) items from Canvas", systemImage: "checkmark.seal.fill")
                            .font(.footnote)
                            .foregroundStyle(Theme.mint)
                    }
                } header: {
                    Text("ASU Canvas")
                } footer: {
                    Text("In Canvas, open Calendar, click “Calendar Feed” and copy the link.")
                }

                Section {
                    Toggle("Deadline reminders", isOn: $store.notificationsOn)
                    Toggle("Daily finance news at 8 AM", isOn: $dailyNews)
                } header: {
                    Text("Notifications")
                } footer: {
                    Text("Deadline reminders arrive the day before and 3 hours before each deadline.")
                }

                Section {
                    Button {
                        Task { await store.refresh() }
                    } label: {
                        Label("Sync now", systemImage: "arrow.clockwise")
                    }
                    if let t = store.lastSynced {
                        LabeledContent("Last synced", value: t.formatted(date: .omitted, time: .shortened))
                    }
                }
            }
            .formStyle(.grouped)
            .scrollContentBackground(.hidden)
            .background(AppBackground())
            .navigationTitle("Settings")
            .inlineTitle()
            .onAppear { feedDraft = store.canvasFeed }
            .onChange(of: dailyNews) { _, on in
                Task {
                    if on { await NotificationService.requestPermission() }
                    NotificationService.scheduleDailyNews(enabled: on)
                }
            }
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }
}
