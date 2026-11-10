import SwiftUI

struct SceneDetailView: View {
    var id: String
    @Environment(APIClient.self) private var api
    @Environment(AppNavigation.self) private var navigation
    @Environment(\.dismiss) private var dismiss
    @Environment(\.openURL) private var openURL
    @State private var store = LoadStore<Scene>()
    @State private var selectedFrame: String?
    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    if let error = store.error { ErrorNotice(message: error) { Task { await load() } } }
                    if let scene = store.value {
                        RemoteImage(path: selectedFrame ?? scene.image).frame(height: 320).clipShape(.rect(cornerRadius: 10))
                        if let frames = scene.frame_urls, frames.count > 1 {
                            ScrollView(.horizontal) {
                                HStack {
                                    ForEach(frames, id: \.self) { frame in
                                        Button { selectedFrame = frame } label: {
                                            RemoteImage(path: frame).frame(width: 120, height: 80).clipShape(.rect(cornerRadius: 6))
                                                .overlay(RoundedRectangle(cornerRadius: 6).stroke(selectedFrame == frame ? Color.accentColor : .clear, lineWidth: 2))
                                        }.buttonStyle(.plain).accessibilityLabel("Show frame \((frames.firstIndex(of: frame) ?? 0) + 1)")
                                    }
                                }
                            }
                        }
                        Text(scene.displayTitle).font(.title2).fontWeight(.semibold)
                        Text("at \(scene.timestamp ?? "0:00")").font(.subheadline.monospacedDigit()).foregroundStyle(.secondary)
                        if let description = scene.description, !description.isEmpty { Text(description) }
                        HStack {
                            Button("Open at \(scene.timestamp ?? "0:00") ↗") { if let url = URL(string: scene.link) { openURL(url) } }.buttonStyle(.borderedProminent)
                            if let url = URL(string: scene.link) { ShareLink(item: url) }
                        }
                        if let source = scene.source {
                            NavigationLink {
                                SourceDetailView(id: source.id)
                            } label: {
                                VStack(alignment: .leading) {
                                    Text("From \(source.displayTitle)")
                                    Text(source.author.hasPrefix("@") ? source.author : "@\(source.author)").font(.subheadline).foregroundStyle(.secondary)
                                }
                            }
                        }
                        if let tags = scene.tags {
                            ForEach(["technique", "style", "format", "motion", "medium", "palette", "concepts"], id: \.self) { facet in
                                if let values = tags[facet], !values.isEmpty {
                                    Text(facet.capitalized).font(.headline)
                                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 120))], alignment: .leading) {
                                        ForEach(values, id: \.self) { tag in
                                            Button(tag) {
                                                navigation.focus("idea:\(facet):\(tag)")
                                                dismiss()
                                            }.buttonStyle(.bordered).tint(facetColor(facet))
                                        }
                                    }
                                }
                            }
                        }
                    } else if store.loading { ProgressView().frame(maxWidth: .infinity).padding(80) }
                }.padding().frame(maxWidth: 850).frame(maxWidth: .infinity)
            }.navigationTitle("Scene")
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } } }
            .task(id: id) { await load() }
            .onChange(of: navigation.mapFocus) { dismiss() }
        }
        #if os(macOS)
        .frame(minWidth: 650, idealWidth: 800, minHeight: 650)
        #endif
    }
    private func load() async { await store.load { try await api.request("scenes/\(id)") } }
}

struct SourceDetailView: View {
    var id: String
    @Environment(APIClient.self) private var api
    @State private var store = LoadStore<Source>()
    @State private var detail: ItemID?
    @State private var sending = false
    @State private var actionError: String?
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                if let error = store.error { ErrorNotice(message: error) { Task { await load() } } }
                if let error = actionError { Text(error).foregroundStyle(.red) }
                if let source = store.value {
                    Text(source.displayTitle).font(.title2)
                    Text(source.author.hasPrefix("@") ? source.author : "@\(source.author)").foregroundStyle(.secondary)
                    HStack {
                        if let url = URL(string: source.url) { Link("Open source ↗", destination: url) }
                        Spacer()
                        Button { Task { await vote(source.verdict == "dislike" ? "clear" : "dislike") } } label: {
                            Label("Dislike", systemImage: source.verdict == "dislike" ? "xmark.circle.fill" : "xmark.circle")
                        }.tint(source.verdict == "dislike" ? .red : .secondary)
                        Button { Task { await vote(source.verdict == "like" ? "clear" : "like") } } label: {
                            Label("Like", systemImage: source.verdict == "like" ? "heart.fill" : "heart")
                        }.tint(source.verdict == "like" ? .pink : .secondary)
                    }.buttonStyle(.bordered).disabled(sending)
                    HStack {
                        if let platform = source.platform { Text(platform.capitalized) }
                        if let duration = source.duration { Text("\(Int(duration) / 60):\(String(format: "%02d", Int(duration) % 60))") }
                        if let origin = source.origin { Text(origin.capitalized) }
                    }.font(.subheadline).foregroundStyle(.secondary)
                    if let pitch = source.pitch, !pitch.isEmpty { Text(pitch) }
                    if let status = source.status { Text(status.capitalized).font(.caption).foregroundStyle(.secondary) }
                    let scenes = source.scenes ?? []
                    if scenes.isEmpty { ContentUnavailableView("No scenes yet", systemImage: "photo.stack") }
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 155, maximum: 280), alignment: .top)], spacing: 20) {
                        ForEach(scenes) { scene in
                            Button { detail = ItemID(id: scene.id) } label: { SceneCard(scene: scene) }.buttonStyle(.plain)
                        }
                    }
                } else if store.loading { ProgressView().frame(maxWidth: .infinity).padding(80) }
            }.padding()
        }.navigationTitle("Source")
        .task(id: id) { await load() }
        .sheet(item: $detail) { SceneDetailView(id: $0.id) }
    }
    private func load() async { await store.load { try await api.request("sources/\(id)") } }
    private func vote(_ verdict: String) async {
        sending = true; actionError = nil
        do { try await api.swipe(id, verdict); await load() } catch { actionError = error.localizedDescription }
        sending = false
    }
}
