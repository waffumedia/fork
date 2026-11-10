import SwiftUI

struct TodayView: View {
    @Environment(APIClient.self) private var api
    @Environment(AppNavigation.self) private var navigation
    @Environment(\.openURL) private var openURL
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var store = LoadStore<TodayResponse>()
    @State private var sceneIndex = 0
    @State private var offset: CGFloat = 0
    @State private var sending = false
    @State private var undoIDs: [String] = []
    @State private var actionError: String?
    private var current: Source? { store.value?.items.first { $0.verdict == nil } }
    private var scenes: [Scene] { current?.scenes ?? [] }
    private var scene: Scene? { scenes.isEmpty ? nil : scenes[min(sceneIndex, scenes.count - 1)] }
    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                if let error = store.error { ErrorNotice(message: error) { Task { await reload() } } }
                if let error = actionError { Text(error).foregroundStyle(.red) }
                if let today = store.value {
                    HStack { Spacer(); Text("\(today.items.filter { $0.verdict == nil }.count) of \(today.total) left").foregroundStyle(.secondary) }
                    if today.total == 0 {
                        ContentUnavailableView("Grokbot hasn't sent today's picks yet", systemImage: "tray", description: Text("Pull to refresh for new picks."))
                    } else if let item = current {
                        card(item)
                        HStack(spacing: 40) {
                            Button { Task { await vote("dislike") } } label: { Image(systemName: "xmark").frame(width: 40, height: 40) }
                                .keyboardShortcut(.leftArrow, modifiers: []).accessibilityLabel("Dislike")
                            Button { Task { await undo() } } label: { Image(systemName: "arrow.uturn.backward").frame(width: 40, height: 40) }
                                .keyboardShortcut("z", modifiers: .command).disabled(undoIDs.isEmpty).accessibilityLabel("Undo swipe")
                            Button { Task { await vote("like") } } label: { Image(systemName: "heart").frame(width: 40, height: 40) }
                                .keyboardShortcut(.rightArrow, modifiers: []).accessibilityLabel("Like")
                        }.buttonStyle(.bordered).buttonBorderShape(.circle).disabled(sending)
                    } else {
                        ContentUnavailableView {
                            Label("Done for today · \(today.items.filter { $0.verdict == "like" }.count) liked", systemImage: "checkmark.circle")
                        } actions: { Button("Go to Map") { navigation.selection = .map } }
                        if !undoIDs.isEmpty { Button("Undo last swipe") { Task { await undo() } }.keyboardShortcut("z", modifiers: .command).disabled(sending) }
                    }
                } else if store.loading { ProgressView().padding(80) }
            }.padding().frame(maxWidth: 680).frame(maxWidth: .infinity)
        }
        .navigationTitle("Today")
        .refreshable { await reload() }
        .toolbar { Button("Refresh", systemImage: "arrow.clockwise") { Task { await reload() } }.disabled(sending) }
        .task(id: api.revision) { if !sending { await reload() } }
        .onChange(of: current?.id) { sceneIndex = 0 }
    }
    private func card(_ item: Source) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Button {
                if !scenes.isEmpty { sceneIndex = (sceneIndex + 1) % scenes.count }
            } label: {
                RemoteImage(path: scene?.image).frame(height: 320).clipShape(.rect(cornerRadius: 12))
            }.buttonStyle(.plain).accessibilityLabel("Next scene")
            HStack(spacing: 6) {
                Spacer()
                ForEach(Array(scenes.enumerated()), id: \.element.id) { index, _ in
                    Button { sceneIndex = index } label: {
                        Image(systemName: index == sceneIndex ? "circle.fill" : "circle").font(.system(size: 7))
                    }.buttonStyle(.plain).accessibilityLabel("Scene \(index + 1) of \(scenes.count)")
                }
                Spacer()
            }
            Text(item.displayTitle).font(.title2).fontWeight(.semibold)
            HStack {
                AuthorBoardLink(author: item.author)
                if let duration = item.duration { Text("· \(Int(duration) / 60):\(String(format: "%02d", Int(duration) % 60))") }
                Text("· \(item.origin == "grok" ? "Grok pick" : "Manual pick")")
            }.font(.subheadline).foregroundStyle(.secondary)
            if let pitch = item.pitch, !pitch.isEmpty { Text(pitch) }
            Button("Open at \(scene?.timestamp ?? "0:00") ↗") {
                if let url = URL(string: scene?.link ?? item.url) { openURL(url) }
            }.buttonStyle(.bordered)
        }
        .offset(x: offset).rotationEffect(.degrees(reduceMotion ? 0 : Double(offset / 30)))
        .gesture(DragGesture().onChanged { if !sending { offset = $0.translation.width } }.onEnded {
            guard !sending else { return }
            if abs($0.translation.width) > 120 { let verdict = $0.translation.width > 0 ? "like" : "dislike"; Task { await vote(verdict) } }
            else { withAnimation(.spring) { offset = 0 } }
        })
    }
    private func reload() async { await store.load { try await api.request("today") } }
    private func vote(_ verdict: String) async {
        guard let item = current, !sending else { return }
        sending = true; actionError = nil
        withAnimation(reduceMotion ? nil : .easeIn(duration: 0.18)) { offset = verdict == "like" ? 1000 : -1000 }
        do {
            try await api.swipe(item.id, verdict)
            try? await Task.sleep(for: .milliseconds(180))
            if let i = store.value?.items.firstIndex(where: { $0.id == item.id }) { store.value?.items[i].verdict = verdict }
            undoIDs.append(item.id)
        } catch { actionError = error.localizedDescription }
        offset = 0; sending = false
    }
    private func undo() async {
        guard let id = undoIDs.last, !sending else { return }
        sending = true; actionError = nil
        do {
            try await api.swipe(id, "clear")
            undoIDs.removeLast()
            await reload()
        } catch { actionError = error.localizedDescription }
        sending = false
    }
}
