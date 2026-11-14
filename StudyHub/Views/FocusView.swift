import SwiftUI
import UIKit

// MARK: - Growth stages

enum Growth {
    /// Milestones by total minutes focused in one sitting.
    static let milestones: [(minutes: Double, name: String)] = [
        (25, "Plant 🌱"),
        (50, "Tree 🌳"),
        (80, "Grove 🌳🌳"),
        (110, "Forest 🌲🌳🌲"),
    ]

    static func title(_ m: Double) -> String {
        switch m {
        case ..<5: return "A seed is planted"
        case ..<15: return "Sprouting"
        case ..<25: return "Growing, leaf by leaf"
        case ..<50: return "Your plant 🌱"
        case ..<80: return "Your tree 🌳"
        case ..<110: return "A little grove 🌳🌳"
        default: return "A forest 🌲🌳🌲"
        }
    }

    static func next(_ m: Double) -> String {
        if let target = milestones.first(where: { $0.minutes > m }) {
            let left = Int((target.minutes - m).rounded(.up))
            return "\(left) min until \(target.name)"
        }
        return "Keep growing your forest"
    }

    static let quotes = [
        "Every minute of focus is a drop of water for your tree.",
        "Small, steady focus grows into something big.",
        "You're planting the future, one minute at a time.",
        "Stay with it. Roots grow before branches.",
        "Deep work now, free time later.",
        "Your future self is cheering for you.",
        "Quiet focus. Strong roots. Big results.",
        "The forest is built one seed at a time.",
    ]

    static let breakQuotes = [
        "Rest is part of the work. Stretch, breathe, drink some water.",
        "Even the tallest trees need sunlight and rest.",
        "Step away from the screen. Your brain is filing everything away.",
        "A short break now means a sharper mind for the next round.",
    ]
}

// MARK: - Timer state

@MainActor
final class FocusTimer: ObservableObject {
    private struct Saved: Codable {
        var blockMinutes: Int
        var accumulated: TimeInterval
        var runningSince: Date?
        var priorFocus: TimeInterval
        var breakEnd: Date?
        var breakOffered: Bool
        var showBreakPrompt: Bool
    }

    static let breakAfter: TimeInterval = 110 * 60
    static let breakLength: TimeInterval = 10 * 60
    private static let saveKey = "focusSession"

    @Published var isPresented = false
    @Published private(set) var blockMinutes = 25
    @Published private(set) var accumulated: TimeInterval = 0
    @Published private(set) var runningSince: Date?
    @Published private(set) var priorFocus: TimeInterval = 0
    @Published private(set) var breakEnd: Date?
    @Published private(set) var breakOffered = false
    @Published private(set) var showBreakPrompt = false

    var isRunning: Bool { runningSince != nil }
    var blockLength: TimeInterval { Double(blockMinutes * 60) }

    init() { restore() }

    func blockElapsed(at now: Date) -> TimeInterval {
        let live = accumulated + (runningSince.map { now.timeIntervalSince($0) } ?? 0)
        return min(live, blockLength)
    }

    func blockLeft(at now: Date) -> TimeInterval { max(0, blockLength - blockElapsed(at: now)) }
    func totalFocus(at now: Date) -> TimeInterval { priorFocus + blockElapsed(at: now) }
    func blockFinished(at now: Date) -> Bool { blockElapsed(at: now) >= blockLength }

    // MARK: Actions

    func start(minutes: Int) {
        blockMinutes = minutes
        accumulated = 0
        priorFocus = 0
        runningSince = .now
        breakEnd = nil
        breakOffered = false
        showBreakPrompt = false
        isPresented = true
        changed()
    }

    func pause() {
        guard let since = runningSince else { return }
        accumulated = min(blockLength, accumulated + Date().timeIntervalSince(since))
        runningSince = nil
        changed()
    }

    func resume() {
        guard runningSince == nil, !blockFinished(at: .now), breakEnd == nil else { return }
        runningSince = .now
        changed()
    }

    /// After a block ends: keep growing the same plant for another block.
    func extend(minutes: Int) {
        priorFocus += blockElapsed(at: .now)
        blockMinutes = minutes
        accumulated = 0
        runningSince = .now
        changed()
    }

    func startBreak() {
        pause()
        showBreakPrompt = false
        breakEnd = Date().addingTimeInterval(Self.breakLength)
        changed()
    }

    func keepFocusing() {
        showBreakPrompt = false
        resume()
        changed()
    }

    /// Break is over: carry on with the current block, or start a new 25 if it was done.
    func backFromBreak() {
        breakEnd = nil
        if blockFinished(at: .now) {
            extend(minutes: 25)
        } else {
            resume()
        }
        changed()
    }

    func finish() {
        let minutes = Int(totalFocus(at: .now) / 60)
        FocusStats.add(minutes: minutes)
        isPresented = false
        runningSince = nil
        accumulated = 0
        priorFocus = 0
        breakEnd = nil
        breakOffered = false
        showBreakPrompt = false
        changed()
    }

    /// Called every second while the focus screen is showing.
    func tick(now: Date) {
        if let since = runningSince, accumulated + now.timeIntervalSince(since) >= blockLength {
            accumulated = blockLength
            runningSince = nil
            changed()
        }
        if !breakOffered, totalFocus(at: now) >= Self.breakAfter {
            breakOffered = true
            pause()
            showBreakPrompt = true
            changed()
        }
    }

    // MARK: Saving and notifications

    private func changed() {
        let saved = Saved(blockMinutes: blockMinutes, accumulated: accumulated, runningSince: runningSince,
                          priorFocus: priorFocus, breakEnd: breakEnd, breakOffered: breakOffered,
                          showBreakPrompt: showBreakPrompt)
        if isPresented, let data = try? JSONEncoder().encode(saved) {
            UserDefaults.standard.set(data, forKey: Self.saveKey)
        } else {
            UserDefaults.standard.removeObject(forKey: Self.saveKey)
        }
        scheduleNotifications()
    }

    private func restore() {
        guard let data = UserDefaults.standard.data(forKey: Self.saveKey),
              let s = try? JSONDecoder().decode(Saved.self, from: data) else { return }
        blockMinutes = s.blockMinutes
        accumulated = s.accumulated
        runningSince = s.runningSince
        priorFocus = s.priorFocus
        breakEnd = s.breakEnd
        breakOffered = s.breakOffered
        showBreakPrompt = s.showBreakPrompt
        isPresented = true
    }

    private func scheduleNotifications() {
        NotificationService.cancelFocus()
        guard isPresented else { return }
        let now = Date()
        if let end = breakEnd {
            NotificationService.scheduleFocus(id: "focus-break-end", at: end,
                                              title: "Break's over 🌱",
                                              body: "Ready for another round? Your tree is waiting.")
            return
        }
        guard isRunning else { return }
        let blockEnd = now.addingTimeInterval(blockLeft(at: now))
        let total = totalFocus(at: now)
        NotificationService.scheduleFocus(id: "focus-end", at: blockEnd,
                                          title: "Focus session complete 🎉",
                                          body: "\(Int((total + blockLeft(at: now)) / 60)) minutes of focus. Add 25 more to keep growing.")
        if !breakOffered {
            let breakAt = now.addingTimeInterval(Self.breakAfter - total)
            if breakAt <= blockEnd {
                NotificationService.scheduleFocus(id: "focus-break", at: breakAt,
                                                  title: "You've been focusing for 1 hour 50 minutes 🌲",
                                                  body: "Take a 10-minute break. " + (Growth.breakQuotes.randomElement() ?? ""))
            }
        }
    }
}

enum FocusStats {
    static func add(minutes: Int) {
        guard minutes > 0 else { return }
        let today = Date().formatted(.iso8601.year().month().day())
        let d = UserDefaults.standard
        if d.string(forKey: "focusDay") != today {
            d.set(today, forKey: "focusDay")
            d.set(0, forKey: "focusMinutesToday")
        }
        d.set(d.integer(forKey: "focusMinutesToday") + minutes, forKey: "focusMinutesToday")
    }
}

// MARK: - Card on the Today screen

struct FocusCard: View {
    @EnvironmentObject var focus: FocusTimer
    @AppStorage("focusPreset") private var preset = 25
    @AppStorage("focusCustom") private var custom = 40
    @AppStorage("focusDay") private var focusDay = ""
    @AppStorage("focusMinutesToday") private var minutesToday = 0

    private var minutes: Int { preset == 0 ? custom : preset }
    private var todayMinutes: Int {
        focusDay == Date().formatted(.iso8601.year().month().day()) ? minutesToday : 0
    }

    var body: some View {
        GlassCard {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Image(systemName: "leaf.fill").foregroundStyle(Theme.mint)
                    Text("Focus").font(.headline)
                    Spacer()
                    if todayMinutes > 0 {
                        Text("\(todayMinutes) min today 🔥")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(Theme.amber)
                    }
                }
                Text("Plant a seed and watch it grow while you study. 25 min grows a plant, 50 a tree, keep going for a forest.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                HStack(spacing: 8) {
                    chip("25 min · Pomodoro", value: 25)
                    chip("50 min", value: 50)
                    chip("Custom", value: 0)
                }
                if preset == 0 {
                    Stepper("\(custom) minutes", value: $custom, in: 5...180, step: 5)
                        .font(.subheadline)
                }
                Button {
                    focus.start(minutes: minutes)
                } label: {
                    Label("Start \(minutes)-minute focus", systemImage: "play.fill")
                        .font(.headline)
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .tint(Theme.mint.opacity(0.85))
                .controlSize(.large)
            }
        }
    }

    private func chip(_ text: String, value: Int) -> some View {
        let selected = preset == value
        return Button {
            withAnimation(.snappy) { preset = value }
        } label: {
            Text(text)
                .font(.caption.weight(.semibold))
                .lineLimit(1)
                .padding(.horizontal, 10)
                .padding(.vertical, 7)
                .foregroundStyle(selected ? Color.white : Theme.mint)
                .background(selected ? Theme.mint.opacity(0.55) : Theme.mint.opacity(0.14), in: Capsule())
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Full-screen focus

struct FocusScreen: View {
    @EnvironmentObject var focus: FocusTimer

    var body: some View {
        TimelineView(.periodic(from: .now, by: 1)) { context in
            let now = context.date
            let total = focus.totalFocus(at: now)
            GeometryReader { geo in
                let landscape = geo.size.width > geo.size.height
                ZStack {
                    FocusSky(minutes: total / 60)
                    if landscape {
                        HStack(spacing: 0) {
                            GrowthScene(minutes: total / 60)
                                .frame(width: geo.size.width * 0.6)
                            panel(now: now, total: total, compact: true)
                                .frame(maxWidth: .infinity)
                        }
                    } else {
                        VStack(spacing: 0) {
                            GrowthScene(minutes: total / 60)
                                .frame(height: geo.size.height * 0.58)
                            panel(now: now, total: total, compact: false)
                                .frame(maxHeight: .infinity)
                        }
                    }
                    overlay(now: now, total: total)
                }
            }
            .onChange(of: Int(now.timeIntervalSince1970)) { _, _ in
                focus.tick(now: now)
            }
        }
        .statusBarHidden()
        .persistentSystemOverlays(.hidden)
        .onAppear { UIApplication.shared.isIdleTimerDisabled = true }
        .onDisappear { UIApplication.shared.isIdleTimerDisabled = false }
        .preferredColorScheme(.dark)
    }

    private func panel(now: Date, total: TimeInterval, compact: Bool) -> some View {
        let minutes = total / 60
        let quote = Growth.quotes[(Int(minutes) / 5) % Growth.quotes.count]
        return VStack(spacing: compact ? 10 : 14) {
            Text(Growth.title(minutes))
                .font(.system(compact ? .title3 : .title2, design: .rounded).weight(.bold))
                .foregroundStyle(Color.white)
                .multilineTextAlignment(.center)
            Text(Growth.next(minutes))
                .font(.subheadline)
                .foregroundStyle(Color.white.opacity(0.7))
            Text(clock(focus.blockLeft(at: now)))
                .font(.system(size: compact ? 52 : 64, weight: .light, design: .rounded))
                .monospacedDigit()
                .foregroundStyle(Color.white.opacity(0.42))
            Text("\(focus.blockMinutes)-min block · \(Int(minutes)) min focused")
                .font(.caption)
                .foregroundStyle(Color.white.opacity(0.45))
            Text(quote)
                .font(.system(.callout, design: .serif).italic())
                .foregroundStyle(Color.white.opacity(0.7))
                .multilineTextAlignment(.center)
                .padding(.horizontal, 24)
            HStack(spacing: 12) {
                if !focus.blockFinished(at: now) {
                    Button(focus.isRunning ? "Pause" : "Resume") {
                        focus.isRunning ? focus.pause() : focus.resume()
                    }
                    .buttonStyle(.bordered)
                }
                Button("End") { focus.finish() }
                    .buttonStyle(.bordered)
            }
            .tint(Color.white.opacity(0.6))
            .opacity(0.75)
        }
        .padding(.vertical, 12)
        .padding(.horizontal, 16)
    }

    @ViewBuilder
    private func overlay(now: Date, total: TimeInterval) -> some View {
        if let end = focus.breakEnd {
            BreakCard(end: end, now: now)
        } else if focus.showBreakPrompt {
            PromptCard(
                emoji: "🌲",
                title: "You've been focusing for 1 hour 50 minutes",
                message: "Amazing work. Take a 10-minute break so you come back sharper.\n\n“\(Growth.breakQuotes[Int(total) % Growth.breakQuotes.count])”",
                primary: PromptAction(title: "Start 10-minute break") { focus.startBreak() },
                secondary: PromptAction(title: "Keep focusing") { focus.keepFocusing() },
                tertiary: nil
            )
        } else if focus.blockFinished(at: now) {
            let minutes = focus.blockMinutes
            let same: PromptAction? = minutes == 25 ? nil
                : PromptAction(title: "+\(minutes) more minutes") { focus.extend(minutes: minutes) }
            PromptCard(
                emoji: "🎉",
                title: "Session complete!",
                message: "You focused for \(Int(total / 60)) minutes. \(Growth.title(total / 60)). Keep going to grow it bigger.",
                primary: PromptAction(title: "+25 more minutes") { focus.extend(minutes: 25) },
                secondary: PromptAction(title: "Finish") { focus.finish() },
                tertiary: same
            )
        }
    }

    private func clock(_ t: TimeInterval) -> String {
        let s = Int(t.rounded(.up))
        return s >= 3600
            ? String(format: "%d:%02d:%02d", s / 3600, (s % 3600) / 60, s % 60)
            : String(format: "%d:%02d", s / 60, s % 60)
    }
}

private struct PromptAction {
    let title: String
    let action: () -> Void
}

private struct PromptCard: View {
    let emoji: String
    let title: String
    let message: String
    let primary: PromptAction
    let secondary: PromptAction
    let tertiary: PromptAction?

    var body: some View {
        ZStack {
            Color.black.opacity(0.45).ignoresSafeArea()
            VStack(spacing: 14) {
                Text(emoji).font(.system(size: 44))
                Text(title)
                    .font(.system(.title3, design: .rounded).weight(.bold))
                    .multilineTextAlignment(.center)
                Text(message)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                Button(action: primary.action) {
                    Text(primary.title).font(.headline).frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .tint(Theme.mint.opacity(0.85))
                .controlSize(.large)
                if let t = tertiary {
                    Button(action: t.action) { Text(t.title).frame(maxWidth: .infinity) }
                        .buttonStyle(.bordered)
                        .controlSize(.large)
                }
                Button(secondary.title, action: secondary.action)
                    .foregroundStyle(.secondary)
            }
            .padding(24)
            .frame(maxWidth: 380)
            .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 28, style: .continuous))
            .padding(24)
        }
    }
}

private struct BreakCard: View {
    @EnvironmentObject var focus: FocusTimer
    let end: Date
    let now: Date

    var body: some View {
        let left = max(0, end.timeIntervalSince(now))
        ZStack {
            Color.black.opacity(0.5).ignoresSafeArea()
            VStack(spacing: 14) {
                Text("☕️").font(.system(size: 44))
                Text(left > 0 ? "Break time" : "Break's over!")
                    .font(.system(.title3, design: .rounded).weight(.bold))
                Text(String(format: "%d:%02d", Int(left) / 60, Int(left) % 60))
                    .font(.system(size: 48, weight: .light, design: .rounded))
                    .monospacedDigit()
                    .opacity(left > 0 ? 1 : 0.4)
                Text("“\(Growth.breakQuotes[Int(end.timeIntervalSince1970) % Growth.breakQuotes.count])”")
                    .font(.system(.callout, design: .serif).italic())
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                Button {
                    focus.backFromBreak()
                } label: {
                    Text(left > 0 ? "I'm ready, back to focus" : "Back to focus").font(.headline).frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .tint(Theme.mint.opacity(0.85))
                .controlSize(.large)
                Button("Finish for now") { focus.finish() }
                    .foregroundStyle(.secondary)
            }
            .padding(24)
            .frame(maxWidth: 380)
            .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 28, style: .continuous))
            .padding(24)
        }
    }
}

// MARK: - The scene: sky, hill, and the growing plant/tree/forest

private struct FocusSky: View {
    let minutes: Double

    var body: some View {
        let warmth = min(minutes / 110, 1)
        ZStack {
            LinearGradient(
                colors: [
                    Color(red: 0.05, green: 0.06, blue: 0.16),
                    Color(red: 0.12 + 0.12 * warmth, green: 0.10 + 0.06 * warmth, blue: 0.30),
                ],
                startPoint: .top, endPoint: .bottom
            )
            Canvas { ctx, size in
                // A few still stars
                let stars: [(CGFloat, CGFloat, CGFloat)] = [
                    (0.12, 0.08, 1.6), (0.3, 0.15, 1.1), (0.55, 0.06, 1.4), (0.78, 0.12, 1.8),
                    (0.9, 0.22, 1.2), (0.22, 0.28, 1.0), (0.66, 0.24, 1.3), (0.43, 0.32, 0.9),
                ]
                for (x, y, r) in stars {
                    let rect = CGRect(x: x * size.width - r, y: y * size.height - r, width: r * 2, height: r * 2)
                    ctx.fill(Path(ellipseIn: rect), with: .color(Color.white.opacity(0.55)))
                }
                // Soft moon
                let moon = CGRect(x: size.width * 0.8, y: size.height * 0.06, width: 34, height: 34)
                ctx.fill(Path(ellipseIn: moon.insetBy(dx: -18, dy: -18)), with: .color(Color.white.opacity(0.04)))
                ctx.fill(Path(ellipseIn: moon), with: .color(Color(red: 1, green: 0.95, blue: 0.85).opacity(0.85)))
            }
        }
        .ignoresSafeArea()
    }
}

struct GrowthScene: View {
    let minutes: Double

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 30.0)) { context in
            let t = context.date.timeIntervalSinceReferenceDate
            Canvas { ctx, size in
                draw(ctx: ctx, size: size, time: t)
            }
        }
    }

    private func clamp(_ v: Double) -> Double { min(max(v, 0), 1) }

    private func draw(ctx: GraphicsContext, size: CGSize, time: Double) {
        let w = size.width
        let h = size.height
        let ground = h * 0.82

        // Extra trees that turn the tree into a grove and then a forest (drawn behind).
        let extras: [(x: CGFloat, scale: CGFloat, start: Double)] = [
            (-0.22, 0.72, 54), (0.22, 0.75, 64), (-0.36, 0.6, 78), (0.36, 0.62, 90), (-0.08, 0.5, 104), (0.1, 0.52, 112),
        ]
        for e in extras {
            let g = clamp((minutes - e.start) / 24)
            guard g > 0 else { continue }
            let base = CGPoint(x: w / 2 + e.x * w, y: ground - h * 0.05 * (1 - e.scale))
            drawPlant(ctx: ctx, base: base, maxHeight: h * 0.62 * e.scale, p: g, time: time + Double(e.start), dim: 0.78)
        }

        // Hill
        var hill = Path()
        hill.move(to: CGPoint(x: 0, y: ground + h * 0.02))
        hill.addQuadCurve(to: CGPoint(x: w, y: ground + h * 0.02), control: CGPoint(x: w / 2, y: ground - h * 0.1))
        hill.addLine(to: CGPoint(x: w, y: h))
        hill.addLine(to: CGPoint(x: 0, y: h))
        hill.closeSubpath()
        ctx.fill(hill, with: .linearGradient(
            Gradient(colors: [Color(red: 0.2, green: 0.5, blue: 0.36), Color(red: 0.06, green: 0.2, blue: 0.16)]),
            startPoint: CGPoint(x: 0, y: ground - h * 0.1), endPoint: CGPoint(x: 0, y: h)
        ))

        // The main plant: seed → sprout → plant (25 min) → tree (50 min)
        let p = clamp(minutes / 50)
        drawPlant(ctx: ctx, base: CGPoint(x: w / 2, y: ground - h * 0.055), maxHeight: h * 0.68, p: p, time: time, dim: 1)
    }

    /// p: 0 = seed, 0.5 = full plant (25 min), 1 = full tree (50 min).
    private func drawPlant(ctx: GraphicsContext, base: CGPoint, maxHeight: CGFloat, p: Double, time: Double, dim: Double) {
        let soil = Color(red: 0.32, green: 0.22, blue: 0.14)
        let leaf = Color(red: 0.36, green: 0.85, blue: 0.5).opacity(dim)
        let leafDark = Color(red: 0.16, green: 0.55, blue: 0.32).opacity(dim)
        let trunk = Color(red: 0.45, green: 0.3, blue: 0.18).opacity(dim)

        // Soil mound
        let moundW = maxHeight * 0.22
        ctx.fill(Path(ellipseIn: CGRect(x: base.x - moundW / 2, y: base.y - moundW * 0.12, width: moundW, height: moundW * 0.24)),
                 with: .color(soil.opacity(dim)))

        if p < 0.06 {
            // A seed, gently bobbing
            let bob = CGFloat(sin(time * 2) * 1.5)
            let s = maxHeight * 0.05
            ctx.fill(Path(ellipseIn: CGRect(x: base.x - s / 2, y: base.y - s * 0.9 + bob, width: s, height: s * 0.75)),
                     with: .color(Color(red: 0.7, green: 0.5, blue: 0.28).opacity(dim)))
            return
        }

        let sway = CGFloat(sin(time * 0.9) * 0.025) // gentle breeze
        let height: CGFloat
        if p < 0.5 {
            height = maxHeight * CGFloat(0.08 + 0.42 * (p - 0.06) / 0.44)
        } else {
            height = maxHeight * CGFloat(0.5 + 0.35 * (p - 0.5) / 0.5)
        }
        let top = CGPoint(x: base.x + height * sway, y: base.y - height)

        // Stem / trunk
        var stem = Path()
        stem.move(to: base)
        stem.addQuadCurve(to: top, control: CGPoint(x: base.x - height * 0.04, y: base.y - height * 0.55))
        let stemWidth = p < 0.5 ? max(2.5, maxHeight * 0.012) : maxHeight * CGFloat(0.014 + 0.05 * (p - 0.5) / 0.5)
        ctx.stroke(stem, with: .color(p < 0.5 ? leafDark : trunk), style: StrokeStyle(lineWidth: stemWidth, lineCap: .round))

        if p < 0.5 {
            // Leaf pairs climbing the stem
            let pairs = 1 + Int((p - 0.06) / 0.44 * 5)
            for i in 0..<pairs {
                let t = CGFloat(i + 1) / CGFloat(pairs + 1)
                let at = CGPoint(x: base.x + (top.x - base.x) * t, y: base.y - height * t)
                let len = maxHeight * 0.09 * (0.7 + (1 - t) * 0.5)
                drawLeaf(ctx: ctx, from: at, angle: -0.6 + Double(sway) * 4, length: len, color: i % 2 == 0 ? leaf : leafDark)
                drawLeaf(ctx: ctx, from: at, angle: Double.pi + 0.6 + Double(sway) * 4, length: len, color: i % 2 == 0 ? leafDark : leaf)
            }
            drawLeaf(ctx: ctx, from: top, angle: -Double.pi / 2 + Double(sway) * 4, length: maxHeight * 0.07, color: leaf)
        } else {
            // Canopy fills in from plant to full tree
            let c = CGFloat((p - 0.5) / 0.5)
            let r = maxHeight * (0.1 + 0.2 * c)
            // Branches
            for side in [-1.0, 1.0] {
                var branch = Path()
                let from = CGPoint(x: base.x + (top.x - base.x) * 0.7, y: base.y - height * 0.7)
                branch.move(to: from)
                branch.addLine(to: CGPoint(x: from.x + CGFloat(side) * r * 0.7, y: from.y - r * 0.5))
                ctx.stroke(branch, with: .color(trunk), style: StrokeStyle(lineWidth: stemWidth * 0.5, lineCap: .round))
            }
            let blobs: [(CGFloat, CGFloat, CGFloat, Color)] = [
                (-0.65, 0.2, 0.75, leafDark), (0.65, 0.2, 0.75, leafDark), (0, 0.35, 0.8, leafDark),
                (-0.35, -0.25, 0.8, leaf), (0.35, -0.25, 0.8, leaf), (0, -0.05, 0.95, leaf), (0, -0.55, 0.65, leaf),
            ]
            for (dx, dy, k, color) in blobs {
                let rr = r * k
                let center = CGPoint(x: top.x + dx * r, y: top.y + dy * r)
                ctx.fill(Path(ellipseIn: CGRect(x: center.x - rr, y: center.y - rr, width: rr * 2, height: rr * 2)), with: .color(color))
            }
            // Blossoms once it's a full tree
            if c > 0.85 {
                let dots: [(CGFloat, CGFloat)] = [(-0.5, -0.2), (0.4, -0.45), (0.1, 0.25), (-0.15, -0.6), (0.6, 0.1)]
                for (dx, dy) in dots {
                    let center = CGPoint(x: top.x + dx * r, y: top.y + dy * r)
                    ctx.fill(Path(ellipseIn: CGRect(x: center.x - 3.5, y: center.y - 3.5, width: 7, height: 7)),
                             with: .color(Color(red: 1, green: 0.62, blue: 0.75).opacity(dim)))
                }
            }
        }
    }

    private func drawLeaf(ctx: GraphicsContext, from: CGPoint, angle: Double, length: CGFloat, color: Color) {
        let tip = CGPoint(x: from.x + CGFloat(cos(angle)) * length, y: from.y + CGFloat(sin(angle)) * length)
        let mid = CGPoint(x: (from.x + tip.x) / 2, y: (from.y + tip.y) / 2)
        let nx = -CGFloat(sin(angle)) * length * 0.32
        let ny = CGFloat(cos(angle)) * length * 0.32
        var path = Path()
        path.move(to: from)
        path.addQuadCurve(to: tip, control: CGPoint(x: mid.x + nx, y: mid.y + ny))
        path.addQuadCurve(to: from, control: CGPoint(x: mid.x - nx, y: mid.y - ny))
        ctx.fill(path, with: .color(color))
    }
}
