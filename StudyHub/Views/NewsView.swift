import SwiftUI
import WebKit

struct NewsView: View {
    @State private var topic: NewsTopic = .top
    @State private var articles: [NewsArticle] = []
    @State private var loading = false
    @State private var errorText: String?

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    header
                    topicChips
                    if loading && articles.isEmpty {
                        ProgressView().frame(maxWidth: .infinity).padding(.vertical, 40)
                    }
                    if let e = errorText, articles.isEmpty {
                        EmptyState(icon: "wifi.exclamationmark", title: "Couldn't load news", message: e)
                    }
                    if let lead = articles.first {
                        NavigationLink(value: lead) {
                            LeadStoryCard(article: lead)
                        }
                        .buttonStyle(.plain)
                    }
                    ForEach(articles.dropFirst()) { article in
                        NavigationLink(value: article) {
                            NewsRow(article: article)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.top, 8)
                .pageColumn()
            }
            .scrollIndicators(.hidden)
            .background(AppBackground())
            .refreshable { await load() }
            .navigationTitle("News")
            .inlineTitle()
            .toolbar {
                ToolbarItem(placement: .primaryAction) { SettingsButton() }
            }
            .task(id: topic) { await load() }
            .navigationDestination(for: NewsArticle.self) { article in
                ArticleView(article: article)
            }
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("DAILY FINANCE BRIEFING")
                .font(.caption.weight(.bold))
                .tracking(1.2)
                .foregroundStyle(Theme.violet)
            Text("Today's headlines")
                .font(.system(.largeTitle, design: .rounded).weight(.bold))
            Text("Google News · last 24 hours")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(.top, 4)
    }

    private var topicChips: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(NewsTopic.allCases) { t in
                    let selected = (t == topic)
                    Button {
                        if t != topic {
                            articles = []
                            topic = t
                        }
                    } label: {
                        Label(t.rawValue, systemImage: t.icon)
                            .font(.caption.weight(.semibold))
                            .padding(.horizontal, 12)
                            .padding(.vertical, 7)
                            .foregroundStyle(selected ? Color.white : Theme.violet)
                            .background(selected ? Theme.violet.opacity(0.85) : Theme.violet.opacity(0.14), in: Capsule())
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    private func load() async {
        loading = true
        defer { loading = false }
        let current = topic
        do {
            let fresh = try await Task { try await NewsService.fetch(current) }.value
            if current == topic { articles = fresh }
            errorText = nil
        } catch {
            if (error as? URLError)?.code != .cancelled, !(error is CancellationError) {
                errorText = "Check your internet connection, then pull down to try again."
            }
        }
    }
}

struct LeadStoryCard: View {
    let article: NewsArticle

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text(article.source.uppercased())
                    .font(.caption.weight(.heavy))
                    .tracking(1.2)
                Spacer()
                if let d = article.published {
                    Text(d.formatted(.relative(presentation: .named)))
                        .font(.caption.weight(.medium))
                }
            }
            .foregroundStyle(Color.white.opacity(0.85))
            Text(article.title)
                .font(.system(.title3, design: .rounded).weight(.bold))
                .foregroundStyle(Color.white)
                .multilineTextAlignment(.leading)
            Label("Read story", systemImage: "arrow.up.right")
                .font(.footnote.weight(.semibold))
                .foregroundStyle(Color.white.opacity(0.9))
        }
        .padding(20)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            LinearGradient(colors: [Theme.sky.opacity(0.9), Theme.violet],
                           startPoint: .topLeading, endPoint: .bottomTrailing),
            in: RoundedRectangle(cornerRadius: 24, style: .continuous)
        )
        .contentShape(Rectangle())
    }
}

struct NewsRow: View {
    let article: NewsArticle

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                Text(article.source)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(Theme.violet)
                    .lineLimit(1)
                if let d = article.published {
                    Text("·").foregroundStyle(.secondary)
                    Text(d.formatted(.relative(presentation: .named)))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            Text(article.title)
                .font(.subheadline.weight(.semibold))
                .multilineTextAlignment(.leading)
                .lineLimit(3)
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.white.opacity(0.05), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .contentShape(Rectangle())
    }
}

/// Reads a story inside StudyHub: headline on top, the article right below.
struct ArticleView: View {
    let article: NewsArticle
    @State private var loading = true

    var body: some View {
        VStack(spacing: 0) {
            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 6) {
                    Text(article.source)
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(Theme.violet)
                    if let d = article.published {
                        Text("·").foregroundStyle(.secondary)
                        Text(d.formatted(.relative(presentation: .named)))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    if loading { ProgressView().controlSize(.small) }
                }
                Text(article.title)
                    .font(.system(.headline, design: .rounded))
                    .lineLimit(3)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(.ultraThinMaterial)

            ArticleWebView(url: article.link, loading: $loading)
        }
        .background(AppBackground())
        .navigationTitle(article.source)
        .inlineTitle()
    }
}

/// An in-app web page that keeps every link inside StudyHub.
struct ArticleWebView: UIViewRepresentable {
    let url: URL
    @Binding var loading: Bool

    func makeCoordinator() -> Coordinator { Coordinator(loading: $loading) }

    func makeUIView(context: Context) -> WKWebView {
        let config = WKWebViewConfiguration()
        config.allowsInlineMediaPlayback = true
        let web = WKWebView(frame: .zero, configuration: config)
        web.navigationDelegate = context.coordinator
        web.uiDelegate = context.coordinator
        web.allowsBackForwardNavigationGestures = true
        web.load(URLRequest(url: url))
        return web
    }

    func updateUIView(_ web: WKWebView, context: Context) {}

    final class Coordinator: NSObject, WKNavigationDelegate, WKUIDelegate {
        var loading: Binding<Bool>

        init(loading: Binding<Bool>) { self.loading = loading }

        func webView(_ webView: WKWebView, didStartProvisionalNavigation navigation: WKNavigation!) {
            loading.wrappedValue = true
        }

        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
            loading.wrappedValue = false
        }

        func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
            loading.wrappedValue = false
        }

        func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
            loading.wrappedValue = false
        }

        /// Links that try to open a new window open in this same view instead.
        func webView(_ webView: WKWebView, createWebViewWith configuration: WKWebViewConfiguration,
                     for navigationAction: WKNavigationAction, windowFeatures: WKWindowFeatures) -> WKWebView? {
            if navigationAction.targetFrame == nil { webView.load(navigationAction.request) }
            return nil
        }

        /// Never hand off to Safari or other apps; only web pages load here.
        func webView(_ webView: WKWebView, decidePolicyFor navigationAction: WKNavigationAction,
                     decisionHandler: @escaping (WKNavigationActionPolicy) -> Void) {
            let scheme = navigationAction.request.url?.scheme?.lowercased() ?? ""
            decisionHandler(scheme == "http" || scheme == "https" || scheme == "about" || scheme == "data" || scheme == "blob" ? .allow : .cancel)
        }
    }
}

/// Gear button at the top right that opens Settings.
struct SettingsButton: View {
    @EnvironmentObject var store: StudyStore
    @State private var show = false

    var body: some View {
        Button {
            show = true
        } label: {
            Image(systemName: "gearshape.fill")
        }
        .accessibilityLabel("Settings")
        .sheet(isPresented: $show) {
            SettingsView()
                .environmentObject(store)
        }
    }
}
