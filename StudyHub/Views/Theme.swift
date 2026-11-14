import SwiftUI

struct AppBackground: View {
    var body: some View {
        ZStack {
            LinearGradient(colors: [Theme.bgTop, Theme.bgBottom], startPoint: .top, endPoint: .bottom)
            Circle()
                .fill(Theme.violet.opacity(0.35))
                .frame(width: 420, height: 420)
                .blur(radius: 130)
                .offset(x: -150, y: -280)
            Circle()
                .fill(Theme.sky.opacity(0.20))
                .frame(width: 360, height: 360)
                .blur(radius: 130)
                .offset(x: 170, y: 300)
        }
        .ignoresSafeArea()
    }
}

struct GlassCard<Content: View>: View {
    var padding: CGFloat = 16
    @ViewBuilder var content: Content

    var body: some View {
        content
            .padding(padding)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 22, style: .continuous)
                    .strokeBorder(Color.white.opacity(0.08))
            )
    }
}

struct ProgressRing: View {
    var progress: Double
    var lineWidth: CGFloat = 10
    var colors: [Color] = [Theme.violet, Theme.sky]

    var body: some View {
        ZStack {
            Circle().stroke(Color.white.opacity(0.1), lineWidth: lineWidth)
            Circle()
                .trim(from: 0, to: max(0.001, min(progress, 1)))
                .stroke(
                    AngularGradient(colors: colors + [colors[0]], center: .center),
                    style: StrokeStyle(lineWidth: lineWidth, lineCap: .round)
                )
                .rotationEffect(.degrees(-90))
        }
        .animation(.easeInOut(duration: 0.5), value: progress)
    }
}

struct KindChip: View {
    let kind: ItemKind

    var body: some View {
        Label(kind.label, systemImage: kind.icon)
            .font(.caption2.weight(.bold))
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .foregroundStyle(kind.color)
            .background(kind.color.opacity(0.16), in: Capsule())
    }
}

struct SectionHeader: View {
    let title: String
    var count: Int? = nil

    var body: some View {
        HStack(alignment: .firstTextBaseline) {
            Text(title).font(.system(.title3, design: .rounded).weight(.bold))
            if let c = count, c > 0 {
                Text("\(c)")
                    .font(.caption.weight(.bold))
                    .padding(.horizontal, 7)
                    .padding(.vertical, 2)
                    .background(Color.white.opacity(0.12), in: Capsule())
            }
            Spacer()
        }
    }
}

struct StatTile: View {
    let value: String
    let label: String
    let color: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(value)
                .font(.system(.title, design: .rounded).weight(.heavy))
                .foregroundStyle(color)
                .monospacedDigit()
            Text(label)
                .font(.caption2.weight(.semibold))
                .foregroundStyle(.secondary)
                .lineLimit(2)
        }
        .padding(14)
        .frame(width: 96, height: 86, alignment: .leading)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
    }
}

struct EmptyState: View {
    let icon: String
    let title: String
    let message: String

    var body: some View {
        VStack(spacing: 10) {
            Image(systemName: icon)
                .font(.system(size: 44))
                .foregroundStyle(Theme.violet.gradient)
            Text(title).font(.headline)
            Text(message).font(.subheadline).foregroundStyle(.secondary).multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 40)
    }
}

struct DueBadge: View {
    let date: Date

    var body: some View {
        TimelineView(.periodic(from: .now, by: 60)) { context in
            let seconds = date.timeIntervalSince(context.date)
            Text(Fmt.short(seconds))
                .font(.caption.weight(.bold).monospacedDigit())
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .foregroundStyle(color(seconds))
                .background(color(seconds).opacity(0.15), in: Capsule())
        }
    }

    private func color(_ s: TimeInterval) -> Color {
        if s < 0 { return Theme.coral }
        if s < 86400 { return Theme.amber }
        if s < 3 * 86400 { return Theme.sky }
        return Color.white.opacity(0.6)
    }
}

struct RefreshButton: View {
    @EnvironmentObject var store: StudyStore

    var body: some View {
        Button {
            Task { await store.refresh() }
        } label: {
            if store.isRefreshing {
                ProgressView().controlSize(.small)
            } else {
                Image(systemName: "arrow.clockwise")
            }
        }
        .disabled(store.isRefreshing)
        .help("Sync now")
    }
}

struct SyncStatusLine: View {
    @EnvironmentObject var store: StudyStore

    var body: some View {
        HStack(spacing: 6) {
            if store.isRefreshing {
                ProgressView().controlSize(.mini)
                Text("Syncing…")
            } else if let err = store.canvasError {
                Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(Theme.amber)
                Text("Canvas: \(err)").lineLimit(1)
            } else if let t = store.lastSynced {
                Image(systemName: "checkmark.icloud.fill").foregroundStyle(Theme.mint)
                Text("Synced \(t.formatted(date: .omitted, time: .shortened))")
            }
        }
        .font(.caption)
        .foregroundStyle(.secondary)
    }
}

extension View {
    /// Small title bar on iPhone/iPad; no-op on Mac.
    @ViewBuilder func inlineTitle() -> some View {
        #if os(iOS)
        self.navigationBarTitleDisplayMode(.inline)
        #else
        self
        #endif
    }

    /// Keyboard setup for pasting links.
    @ViewBuilder func urlEntry() -> some View {
        #if os(iOS)
        self.keyboardType(.URL).textInputAutocapitalization(.never).autocorrectionDisabled()
        #else
        self.autocorrectionDisabled()
        #endif
    }

    /// Centered, readable column on wide screens (iPad, Mac).
    func pageColumn() -> some View {
        self
            .padding(.horizontal, 18)
            .padding(.bottom, 32)
            .frame(maxWidth: 820)
            .frame(maxWidth: .infinity)
    }

    @ViewBuilder func sheetSize() -> some View {
        #if os(macOS)
        self.frame(minWidth: 460, minHeight: 540)
        #else
        self
        #endif
    }
}
