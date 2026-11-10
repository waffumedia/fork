import SwiftUI

struct AuthorBoardLink: View {
    var author: String
    private var handle: String { author.hasPrefix("@") ? String(author.dropFirst()) : author }
    var body: some View {
        NavigationLink { BoardDetailView(id: "account:\(handle)") } label: { Text("@\(handle)") }
            .buttonStyle(.plain).foregroundStyle(.secondary)
            .accessibilityLabel("Open @\(handle) board")
    }
}

struct BoardsView: View {
    @Environment(APIClient.self) private var api
    @State private var store = LoadStore<BoardsIndex>()
    @State private var category = "Accounts"
    @State private var query = ""
    var body: some View {
        VStack(spacing: 0) {
            Picker("Boards", selection: $category) {
                Text("Accounts").tag("Accounts")
                Text("Videos").tag("Videos")
            }.pickerStyle(.segmented).padding()
            ScrollView {
                if let error = store.error { ErrorNotice(message: error) { Task { await load() } } }
                if store.loading { ProgressView().padding() }
                if let index = store.value {
                    let accounts = index.accounts.filter { query.isEmpty || $0.handle.localizedCaseInsensitiveContains(query) }
                    let videos = index.videos.filter { query.isEmpty || "\($0.title) \($0.author) \($0.note ?? "")".localizedCaseInsensitiveContains(query) }
                    if category == "Accounts" ? accounts.isEmpty : videos.isEmpty { ContentUnavailableView.search(text: query) }
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 230, maximum: 350), alignment: .top)], spacing: 24) {
                        if category == "Accounts" {
                            ForEach(accounts) { account in
                                NavigationLink { BoardDetailView(id: account.id) } label: {
                                    VStack(alignment: .leading, spacing: 8) {
                                        Grid(horizontalSpacing: 3, verticalSpacing: 3) {
                                            ForEach(0..<2) { row in
                                                GridRow {
                                                    ForEach(0..<2) { col in
                                                        let i = row * 2 + col
                                                        RemoteImage(path: i < account.covers.count ? account.covers[i] : nil, fit: false, maxPixel: 320).frame(height: 90)
                                                    }
                                                }
                                            }
                                        }.clipShape(.rect(cornerRadius: 10))
                                        Text("@\(account.handle)").font(.headline)
                                        Text("\(account.sources) posts · \(account.scenes) scenes").font(.subheadline).foregroundStyle(.secondary)
                                    }
                                }.buttonStyle(.plain)
                            }
                        } else {
                            ForEach(videos) { video in
                                VStack(alignment: .leading, spacing: 8) {
                                    NavigationLink { BoardDetailView(id: video.id) } label: {
                                        VStack(alignment: .leading, spacing: 8) {
                                            RemoteImage(path: video.cover, maxPixel: 480).frame(height: 180).clipShape(.rect(cornerRadius: 10))
                                            Text(video.title.isEmpty ? "Untitled video" : video.title).font(.headline).lineLimit(2)
                                        }
                                    }.buttonStyle(.plain)
                                    AuthorBoardLink(author: video.author).font(.subheadline)
                                    if let note = video.note, !note.isEmpty { Text(note).font(.caption).foregroundStyle(.secondary).lineLimit(3) }
                                }
                            }
                        }
                    }.padding()
                }
            }.refreshable { await load() }
        }.navigationTitle("Boards")
        .searchable(text: $query, prompt: "Search boards")
        .toolbar { Button("Refresh", systemImage: "arrow.clockwise") { Task { await load() } } }
        .task(id: "\(api.server)|\(api.revision)") { await load() }
    }
    private func load() async { await store.load { try await api.request("boards") } }
}

struct BoardDetailView: View {
    var id: String
    @Environment(APIClient.self) private var api
    @State private var store = LoadStore<Board>()
    @State private var layout: BoardLayout?
    var body: some View {
        VStack(spacing: 0) {
            if let error = store.error { ErrorNotice(message: error) { Task { await load() } } }
            if let board = store.value, let layout {
                HStack {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(board.title).font(.headline)
                        Text(board.subtitle).font(.subheadline).foregroundStyle(.secondary)
                    }
                    Spacer()
                    if let profile = board.profile, let url = URL(string: profile) { Link("Profile ↗", destination: url) }
                }.padding()
                Divider()
                if board.groups.isEmpty { ContentUnavailableView("No scenes yet", systemImage: "rectangle.3.group") }
                else { BoardCanvas(layout: layout).id("\(api.server)|\(board.id)") }
            } else if store.loading { ProgressView().frame(maxWidth: .infinity, maxHeight: .infinity) }
        }.navigationTitle("Board")
        .toolbar { Button("Refresh", systemImage: "arrow.clockwise") { Task { await load() } } }
        .task(id: "\(api.server)|\(api.revision)|\(id)") { await load() }
    }
    private func load() async {
        await store.load { try await api.request("boards/\(id)") }
        if let board = store.value { layout = BoardLayout(board) }
    }
}

private struct BoardCanvas: View {
    var layout: BoardLayout
    @State private var zoom: CGFloat = 1
    @State private var pan = CGSize.zero
    @GestureState private var drag = CGSize.zero
    @GestureState private var magnification: CGFloat = 1
    @State private var detail: ItemID?
    #if os(macOS)
    @State private var scrollOffset: CGFloat = 0
    #endif
    var body: some View {
        GeometryReader { proxy in
            #if os(macOS)
            ScrollView(.vertical) {
                content(proxy.size).frame(height: proxy.size.height).offset(y: scrollOffset)
                    .frame(height: proxy.size.height + 100_000, alignment: .top)
            }.scrollIndicators(.hidden).defaultScrollAnchor(.center)
            .onScrollGeometryChange(for: CGFloat.self) { $0.contentOffset.y } action: { old, new in
                scrollOffset = new
                if abs(new - old) < 2000 { zoom = min(100, max(0.1, zoom * exp((new - old) * 0.003))) }
            }
            #else
            content(proxy.size)
            #endif
        }
        .clipped()
        .overlay(alignment: .bottomTrailing) {
            HStack {
                Button("Zoom out", systemImage: "minus.magnifyingglass") { zoom = max(0.1, zoom / 1.4) }
                Button("Fit", systemImage: "arrow.up.left.and.arrow.down.right") { zoom = 1; pan = .zero }
                Button("Zoom in", systemImage: "plus.magnifyingglass") { zoom = min(100, zoom * 1.4) }
            }.labelStyle(.iconOnly).buttonStyle(.bordered).padding().background(.regularMaterial, in: .rect(cornerRadius: 12)).padding()
        }
        .sheet(item: $detail) { SceneDetailView(id: $0.id) }
    }
    private func content(_ size: CGSize) -> some View {
        let fit = max(0.001, min(max(1, size.width - 64) / layout.bounds.width, max(1, size.height - 64) / layout.bounds.height))
        let scale = min(3, max(0.005, fit * zoom * magnification))
        let origin = CGPoint(x: size.width / 2 + pan.width + drag.width - layout.bounds.midX * scale,
                             y: size.height / 2 + pan.height + drag.height - layout.bounds.midY * scale)
        let viewport = CGRect(x: -origin.x / scale, y: -origin.y / scale, width: size.width / scale, height: size.height / scale)
        let visible = layout.frames.filter { $0.rect.intersects(viewport) }
        let detailed = scale >= 0.45
        return ZStack(alignment: .topLeading) {
            Color(white: 0.93)
            Canvas { context, _ in
                context.translateBy(x: origin.x, y: origin.y)
                context.scaleBy(x: scale, y: scale)
                for frame in visible {
                    context.fill(Path(roundedRect: frame.rect, cornerRadius: 12), with: .color(.white))
                    if !detailed {
                        context.draw(Text(frame.group.title.isEmpty ? "Untitled post" : frame.group.title).font(.system(size: 16)).foregroundColor(.black), in: CGRect(x: frame.rect.minX + 16, y: frame.rect.minY + 12, width: frame.rect.width - 32, height: 56))
                        for i in frame.group.scenes.indices {
                            let rect = frame.cardRect(i)
                            if rect.intersects(viewport) { context.fill(Path(roundedRect: rect, cornerRadius: 6), with: .color(Color(white: 0.82))) }
                        }
                    }
                }
            }.allowsHitTesting(false)
            if detailed {
                ForEach(visible) { frame in
                    let header = CGRect(x: frame.rect.minX + 16, y: frame.rect.minY + 8, width: frame.rect.width - 32, height: 72)
                    if header.intersects(viewport) {
                        BoardFrameHeader(group: frame.group)
                            .frame(width: header.width, height: header.height).scaleEffect(scale)
                            .position(x: origin.x + header.midX * scale, y: origin.y + header.midY * scale)
                    }
                    ForEach(Array(frame.group.scenes.enumerated()), id: \.element.id) { i, scene in
                        let rect = frame.cardRect(i)
                        if rect.intersects(viewport) {
                            Button { detail = ItemID(id: scene.id) } label: { BoardSceneCard(scene: scene) }
                                .buttonStyle(.plain).frame(width: rect.width, height: rect.height).scaleEffect(scale)
                                .position(x: origin.x + rect.midX * scale, y: origin.y + rect.midY * scale)
                        }
                    }
                }
            }
        }.contentShape(Rectangle())
        .gesture(DragGesture(minimumDistance: 5).updating($drag) { value, state, _ in state = value.translation }
            .onEnded { pan.width += $0.translation.width; pan.height += $0.translation.height })
        .simultaneousGesture(MagnifyGesture().updating($magnification) { value, state, _ in state = value.magnification }
            .onEnded { zoom = min(100, max(0.1, zoom * $0.magnification)) })
        .simultaneousGesture(SpatialTapGesture().onEnded { value in
            guard !detailed else { return }
            let p = CGPoint(x: (value.location.x - origin.x) / scale, y: (value.location.y - origin.y) / scale)
            for frame in visible {
                for i in frame.group.scenes.indices where frame.cardRect(i).contains(p) { detail = ItemID(id: frame.group.scenes[i].id); return }
            }
        })
        .accessibilityLabel("Board canvas. Pan to move, pinch to zoom, or use Fit and zoom buttons.")
    }
}

private struct BoardFrameHeader: View {
    var group: BoardGroup
    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                Text(group.title.isEmpty ? "Untitled post" : group.title).font(.subheadline.weight(.semibold)).lineLimit(1)
                if let note = group.note, !note.isEmpty { Text(note).font(.caption).italic().lineLimit(2) }
            }
            Spacer(minLength: 0)
            if group.verdict == "like" || group.origin == "seed" && group.verdict != "dislike" { Image(systemName: "heart.fill").foregroundStyle(.pink).accessibilityLabel("Liked") }
            else if group.verdict == "dislike" { Image(systemName: "xmark").foregroundStyle(.secondary).accessibilityLabel("Disliked") }
            if let url = URL(string: group.url) { Link("Open ↗", destination: url).font(.caption) }
        }.foregroundStyle(.black).environment(\.colorScheme, .light)
    }
}
private struct BoardSceneCard: View {
    var scene: BoardScene
    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            RemoteImage(path: scene.image, maxPixel: 480).frame(height: 120).clipShape(.rect(cornerRadius: 6))
            Text(scene.displayTimestamp).font(.caption.monospacedDigit()).foregroundStyle(.secondary)
            Text(scene.title.isEmpty ? "Scene at \(scene.displayTimestamp)" : scene.title).font(.caption).lineLimit(2)
            Spacer(minLength: 0)
        }.foregroundStyle(.black).environment(\.colorScheme, .light).contentShape(Rectangle())
    }
}
