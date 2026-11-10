import SwiftUI

struct HistoryView: View {
    @Environment(APIClient.self) private var api
    @State private var store = LoadStore<Items<HistoryItem>>()
    @State private var filter = "All"
    @State private var sending = false
    @State private var actionError: String?
    private var items: [HistoryItem] {
        (store.value?.items ?? []).filter { filter == "All" || $0.verdict == (filter == "Liked" ? "like" : "dislike") }
    }
    var body: some View {
        VStack(spacing: 0) {
            Picker("Verdict", selection: $filter) {
                ForEach(["All", "Liked", "Disliked"], id: \.self) { Text($0) }
            }.pickerStyle(.segmented).padding()
            if let error = actionError { Text(error).foregroundStyle(.red) }
            if let error = store.error { ErrorNotice(message: error) { Task { await load() } } }
            if store.loading { ProgressView() }
            List(items) { item in
                HStack(spacing: 12) {
                        NavigationLink { SourceDetailView(id: item.id) } label: {
                            RemoteImage(path: item.cover).frame(width: 70, height: 55).clipShape(.rect(cornerRadius: 6))
                        }.buttonStyle(.plain)
                        VStack(alignment: .leading, spacing: 4) {
                            NavigationLink { SourceDetailView(id: item.id) } label: {
                                Text(item.title.isEmpty ? "Untitled source" : item.title).lineLimit(2)
                            }
                            AuthorBoardLink(author: item.author).font(.subheadline)
                            if let date = item.date { Text(date, style: .relative).font(.caption).foregroundStyle(.secondary) }
                        }
                        Spacer()
                        Image(systemName: item.verdict == "like" ? "heart.fill" : "xmark").foregroundStyle(item.verdict == "like" ? Color.pink : Color.secondary)
                }
                .swipeActions {
                    Button("Clear", role: .destructive) { Task { await update(item.id, "clear") } }
                    Button(item.verdict == "like" ? "Dislike" : "Like") { Task { await update(item.id, item.verdict == "like" ? "dislike" : "like") } }.tint(.accentColor)
                }
                .contextMenu {
                    Button(item.verdict == "like" ? "Dislike" : "Like") { Task { await update(item.id, item.verdict == "like" ? "dislike" : "like") } }
                    Button("Clear verdict", role: .destructive) { Task { await update(item.id, "clear") } }
                }
            }.disabled(sending)
            .overlay { if items.isEmpty && !store.loading && store.error == nil { ContentUnavailableView("No \(filter == "All" ? "swipes" : filter.lowercased() + " picks") yet", systemImage: "clock", description: Text("Your swipe history appears here.")) } }
            .refreshable { await load() }
        }.navigationTitle("History")
        .toolbar { Button("Refresh", systemImage: "arrow.clockwise") { Task { await load() } } }
        .task(id: api.revision) { await load() }
    }
    private func load() async { await store.load { try await api.request("history") } }
    private func update(_ id: String, _ verdict: String) async {
        guard !sending else { return }
        sending = true; actionError = nil
        do { try await api.swipe(id, verdict); await load() } catch { actionError = error.localizedDescription }
        sending = false
    }
}
