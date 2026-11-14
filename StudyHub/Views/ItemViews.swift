import SwiftUI

struct ItemRow: View {
    @EnvironmentObject var store: StudyStore
    let item: StudyItem
    var showDate = false
    @State private var showDetail = false

    var body: some View {
        let done = store.isDone(item)
        HStack(spacing: 12) {
            if item.tracksCompletion {
                Button {
                    withAnimation(.snappy) { store.toggleDone(item) }
                } label: {
                    Image(systemName: done ? "checkmark.circle.fill" : "circle")
                        .font(.title2)
                        .foregroundStyle(done ? Theme.mint : item.kind.color)
                }
                .buttonStyle(.plain)
                .sensoryFeedback(.success, trigger: done)
            } else {
                RoundedRectangle(cornerRadius: 3)
                    .fill(item.tint)
                    .frame(width: 5, height: 34)
            }

            VStack(alignment: .leading, spacing: 3) {
                Text(item.title)
                    .font(.subheadline.weight(.semibold))
                    .strikethrough(done)
                    .foregroundStyle(done ? Color.secondary : Color.primary)
                    .lineLimit(2)
                HStack(spacing: 6) {
                    Image(systemName: item.source.icon)
                    Text(subtitle)
                }
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(1)
            }

            Spacer(minLength: 8)

            if item.tracksCompletion && !done {
                DueBadge(date: item.due)
            }
        }
        .padding(12)
        .background(Color.white.opacity(0.05), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .contentShape(Rectangle())
        .onTapGesture { showDetail = true }
        .sheet(isPresented: $showDetail) {
            ItemDetailView(item: item).environmentObject(store)
        }
    }

    private var subtitle: String {
        var parts: [String] = []
        if let course = item.course { parts.append(course) }
        if showDate { parts.append(item.start.formatted(.dateTime.month(.abbreviated).day())) }
        parts.append(Fmt.time(item))
        return parts.joined(separator: " · ")
    }
}

struct ItemDetailView: View {
    @EnvironmentObject var store: StudyStore
    @Environment(\.dismiss) private var dismiss
    @Environment(\.openURL) private var openURL
    let item: StudyItem
    @State private var errorText: String?

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    KindChip(kind: item.kind)
                    Text(item.title).font(.system(.title2, design: .rounded).weight(.bold))
                    if let course = item.course {
                        Label(course, systemImage: "graduationcap").foregroundStyle(.secondary)
                    }

                    GlassCard {
                        VStack(alignment: .leading, spacing: 10) {
                            Label(item.start.formatted(date: .complete, time: item.isAllDay ? .omitted : .shortened),
                                  systemImage: "clock")
                            if item.tracksCompletion {
                                Label(Fmt.countdown(to: item.due), systemImage: "hourglass")
                            }
                            Label(item.source.label, systemImage: item.source.icon)
                            if let loc = item.location, !loc.isEmpty {
                                Label(loc, systemImage: "mappin.and.ellipse")
                            }
                        }
                        .font(.subheadline)
                    }

                    if let notes = item.notes, !notes.isEmpty {
                        GlassCard {
                            Text(notes).font(.callout).textSelection(.enabled)
                        }
                    }

                    if item.tracksCompletion {
                        Button {
                            withAnimation(.snappy) { store.toggleDone(item) }
                        } label: {
                            Label(store.isDone(item) ? "Mark as not done" : "Mark as done",
                                  systemImage: "checkmark.circle.fill")
                                .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.borderedProminent)
                        .controlSize(.large)
                    }

                    if item.source == .canvas, let url = item.url {
                        Button {
                            openURL(url)
                        } label: {
                            Label("Open in Canvas", systemImage: "safari").frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.large)
                    }

                    if let e = errorText {
                        Text(e).font(.footnote).foregroundStyle(Theme.coral)
                    }
                }
                .padding(20)
            }
            .background(AppBackground())
            .navigationTitle("Details")
            .inlineTitle()
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
        .sheetSize()
    }
}
