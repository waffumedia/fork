import SwiftUI

struct LibraryView: View {
    @Environment(APIClient.self) private var api
    @State private var store = LoadStore<Items<Scene>>()
    @State private var tags: [TagCount] = []
    @State private var query = ""
    @State private var selectedTag: String?
    @State private var liked = true
    @State private var detail: ItemID?
    private var requestKey: String { "\(query)|\(selectedTag ?? "")|\(liked)|\(api.revision)" }
    var body: some View {
        ScrollView {
            VStack(alignment: .leading) {
                ScrollView(.horizontal) {
                    HStack {
                        ForEach(tags.prefix(30)) { tag in
                            Button(tag.tag) { selectedTag = selectedTag == tag.id ? nil : tag.id }
                                .buttonStyle(.bordered).tint(selectedTag == tag.id ? .accentColor : .secondary)
                                .accessibilityLabel("\(tag.facet): \(tag.tag)")
                        }
                    }.padding(.horizontal)
                }
                if let tag = selectedTag { Button("Clear \(tag)", systemImage: "xmark.circle") { selectedTag = nil }.padding(.horizontal) }
                if let error = store.error { ErrorNotice(message: error) { Task { await load() } } }
                if store.loading { ProgressView().frame(maxWidth: .infinity).padding() }
                if let scenes = store.value?.items {
                    if scenes.isEmpty && !store.loading {
                        ContentUnavailableView.search(text: query)
                    } else {
                        LazyVGrid(columns: [GridItem(.adaptive(minimum: 155, maximum: 280), alignment: .top)], alignment: .leading, spacing: 20) {
                            ForEach(scenes) { scene in
                                Button { detail = ItemID(id: scene.id) } label: { SceneCard(scene: scene) }.buttonStyle(.plain)
                            }
                        }.padding()
                    }
                }
            }
        }.navigationTitle("Library")
        .searchable(text: $query, prompt: "Search scenes")
        .toolbar { Toggle("Liked only", isOn: $liked) }
        .refreshable { await load(); await loadTags() }
        .task(id: requestKey) {
            do { try await Task.sleep(for: .milliseconds(250)); try Task.checkCancellation(); await load() } catch { }
        }
        .task(id: api.server) { await loadTags() }
        .sheet(item: $detail) { SceneDetailView(id: $0.id) }
    }
    private func load() async {
        await store.load {
            var params = [URLQueryItem(name: "q", value: query), URLQueryItem(name: "limit", value: "60")]
            if liked { params.append(URLQueryItem(name: "liked", value: "1")) }
            if let selectedTag { params.append(URLQueryItem(name: "tag", value: selectedTag)) }
            return try await api.request("scenes", query: params)
        }
    }
    private func loadTags() async {
        do { let stats: Stats = try await api.request("stats"); tags = stats.tags } catch { store.error = error.localizedDescription }
    }
}
