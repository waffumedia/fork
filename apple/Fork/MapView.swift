import SwiftUI
import Observation

@MainActor @Observable final class MapStore {
    var graph: Graph?
    var positions: [String: CGPoint] = [:]
    var loading = false
    var error: String?
    private var generation = 0
    func load(api: APIClient, mode: String, liked: Bool, focus: String?) async {
        generation += 1
        let current = generation
        loading = true; error = nil
        do {
            var params = [URLQueryItem(name: "mode", value: mode), URLQueryItem(name: "depth", value: "2")]
            if liked { params.append(URLQueryItem(name: "liked", value: "1")) }
            if let focus { params.append(URLQueryItem(name: "focus", value: focus)) }
            let graph: Graph = try await api.request("graph", query: params)
            let fingerprint = graph.nodes.map { "\($0.id):\($0.degree)" }.joined(separator: "|")
            let key = "\(api.server)|\(mode)|\(liked)|\(focus ?? "")|\(fingerprint)"
            let positions = try await GraphLayout.shared.positions(graph: graph, key: key)
            guard current == generation, !Task.isCancelled else { return }
            self.graph = graph; self.positions = positions
        } catch {
            guard current == generation else { return }
            if !Task.isCancelled { self.error = error.localizedDescription }
        }
        if current == generation { loading = false }
    }
}

struct MapView: View {
    @Environment(APIClient.self) private var api
    @Environment(AppNavigation.self) private var navigation
    @State private var store = MapStore()
    @State private var mode = "ideas"
    @State private var liked = true
    @State private var search = ""
    @State private var detail: ItemID?
    private var requestKey: String { "\(mode)|\(liked)|\(navigation.mapFocus ?? "")|\(api.revision)" }
    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Picker("Map mode", selection: $mode) { Text("Ideas").tag("ideas"); Text("Full").tag("full") }
                    .pickerStyle(.segmented).frame(maxWidth: 230)
                Spacer()
                Toggle("Liked only", isOn: $liked).fixedSize()
            }.padding()
            if let focus = navigation.mapFocus {
                HStack {
                    Button("All") { navigation.mapFocus = nil }
                    Image(systemName: "chevron.right").font(.caption)
                    Text(focus.split(separator: ":").dropFirst(2).joined(separator: ":")).lineLimit(1)
                    Spacer()
                }.padding(.horizontal).padding(.bottom, 8)
            }
            if !search.isEmpty {
                List((store.graph?.nodes ?? []).filter { $0.label.localizedCaseInsensitiveContains(search) }.prefix(12)) { node in
                    Button { select(node); search = "" } label: { Label(node.label, systemImage: node.type == "idea" ? "circle.fill" : "photo") }
                }.frame(maxHeight: 180)
            }
            if let error = store.error { ErrorNotice(message: error) { Task { await load() } } }
            ZStack {
                if let graph = store.graph {
                    if graph.nodes.isEmpty && !store.loading {
                        ContentUnavailableView("No connections yet", systemImage: "point.3.connected.trianglepath.dotted", description: Text("Connections appear as scenes receive tags. Try Full or turn off Liked only."))
                    } else {
                        GraphCanvas(graph: graph, positions: store.positions, select: select)
                            .id(requestKey)
                            .overlay(alignment: .bottomLeading) {
                                Text("\(graph.nodes.count) nodes · \(graph.edges.count) connections")
                                    .font(.caption).foregroundStyle(.secondary).padding(8).background(.regularMaterial, in: .rect(cornerRadius: 8)).padding()
                            }
                    }
                }
                if store.loading { ProgressView("Laying out map…").padding().background(.regularMaterial, in: .rect(cornerRadius: 10)) }
            }.frame(maxWidth: .infinity, maxHeight: .infinity)
        }.navigationTitle("Map")
        .searchable(text: $search, prompt: "Find a node")
        .toolbar { Button("Refresh", systemImage: "arrow.clockwise") { Task { await load() } } }
        .task(id: requestKey) { await load() }
        .sheet(item: $detail) { SceneDetailView(id: $0.id) }
    }
    private func select(_ node: GraphNode) {
        if node.type == "idea" { navigation.mapFocus = node.id }
        else { detail = ItemID(id: node.id) }
    }
    private func load() async { await store.load(api: api, mode: mode, liked: liked, focus: navigation.mapFocus) }
}

private struct GraphCanvas: View {
    var graph: Graph
    var positions: [String: CGPoint]
    var select: (GraphNode) -> Void
    @Environment(APIClient.self) private var api
    @State private var pan = CGSize.zero
    @GestureState private var drag = CGSize.zero
    @State private var zoom: CGFloat = 1
    @GestureState private var magnification: CGFloat = 1
    @State private var thumbnails = ThumbnailStore()
    #if os(macOS)
    @State private var scrollOffset: CGFloat = 0
    #endif
    private let bounds: CGRect
    init(graph: Graph, positions: [String: CGPoint], select: @escaping (GraphNode) -> Void) {
        self.graph = graph; self.positions = positions; self.select = select
        let xs = positions.values.map(\.x), ys = positions.values.map(\.y)
        bounds = CGRect(x: xs.min() ?? 0, y: ys.min() ?? 0,
                        width: max(1, (xs.max() ?? 0) - (xs.min() ?? 0)),
                        height: max(1, (ys.max() ?? 0) - (ys.min() ?? 0)))
    }
    private func scale(_ size: CGSize) -> CGFloat { min((size.width - 80) / (bounds.width + 60), (size.height - 80) / (bounds.height + 60)) * zoom * magnification }
    private func point(_ id: String, _ size: CGSize) -> CGPoint {
        let p = positions[id] ?? .zero
        let s = max(0.01, scale(size))
        return CGPoint(x: (p.x - bounds.midX) * s + size.width / 2 + pan.width + drag.width,
                       y: (p.y - bounds.midY) * s + size.height / 2 + pan.height + drag.height)
    }
    var body: some View {
        GeometryReader { proxy in
            #if os(macOS)
            // SwiftUI's native scroll geometry supplies wheel deltas without an AppKit event monitor.
            ScrollView(.vertical) {
                canvas(proxy.size).frame(height: proxy.size.height)
                    .offset(y: scrollOffset)
                    .frame(height: proxy.size.height + 100_000, alignment: .top)
            }.scrollIndicators(.hidden).defaultScrollAnchor(.center)
            .onScrollGeometryChange(for: CGFloat.self) { $0.contentOffset.y } action: { old, new in
                scrollOffset = new
                if abs(new - old) < 2000 { zoom = min(12, max(0.2, zoom * exp((new - old) * 0.003))) }
            }
            #else
            canvas(proxy.size)
            #endif
        }
        .overlay(alignment: .bottomTrailing) {
            HStack {
                Button("Zoom out", systemImage: "minus.magnifyingglass") { zoom = max(0.2, zoom / 1.3) }
                Button("Fit", systemImage: "arrow.up.left.and.arrow.down.right") { zoom = 1; pan = .zero }
                Button("Zoom in", systemImage: "plus.magnifyingglass") { zoom = min(12, zoom * 1.3) }
            }.labelStyle(.iconOnly).buttonStyle(.bordered).padding()
        }
    }
    private func canvas(_ size: CGSize) -> some View {
        let visible = graph.nodes.filter { CGRect(origin: .zero, size: size).insetBy(dx: -40, dy: -40).contains(point($0.id, size)) }
        let imageKey = visible.filter { $0.type == "scene" }.map(\.id).joined(separator: "|")
        return Canvas { context, canvasSize in
            var has = Path(), co = Path(), bridge = Path(), cross = Path()
            for edge in graph.edges {
                let a = point(edge.source, canvasSize), b = point(edge.target, canvasSize)
                switch edge.kind {
                case "has": has.move(to: a); has.addLine(to: b)
                case "co": co.move(to: a); co.addLine(to: b)
                default:
                    if edge.cross == true { cross.move(to: a); cross.addLine(to: b) }
                    else { bridge.move(to: a); bridge.addLine(to: b) }
                }
            }
            context.stroke(has, with: .color(.secondary.opacity(0.15)), lineWidth: 0.5)
            context.stroke(co, with: .color(.secondary.opacity(0.24)), lineWidth: 0.7)
            context.stroke(bridge, with: .color(.secondary.opacity(0.3)), style: StrokeStyle(lineWidth: 0.7, dash: [3, 3]))
            context.stroke(cross, with: .color(.accentColor.opacity(0.5)), style: StrokeStyle(lineWidth: 0.8, dash: [3, 3]))
            for node in visible {
                let p = point(node.id, canvasSize)
                if node.type == "idea" {
                    let r: CGFloat = 4 + min(5, CGFloat(node.count ?? 1) / 10)
                    context.fill(Path(ellipseIn: CGRect(x: p.x - r, y: p.y - r, width: r * 2, height: r * 2)), with: .color(facetColor(node.facet)))
                    if scale(canvasSize) >= 0.65 {
                        context.draw(Text(node.label).font(.caption2).foregroundColor(facetColor(node.facet)), at: CGPoint(x: p.x + r + 3, y: p.y), anchor: .leading)
                    }
                } else {
                    let rect = CGRect(x: p.x - 13, y: p.y - 13, width: 26, height: 26)
                    let shape = Path(roundedRect: rect, cornerRadius: 4)
                    if let image = thumbnails.images[node.id] {
                        var clipped = context
                        clipped.clip(to: shape)
                        clipped.draw(image, in: rect)
                    } else { context.fill(shape, with: .color(.secondary.opacity(0.4))) }
                }
            }
        }
        .contentShape(Rectangle())
        .gesture(DragGesture(minimumDistance: 4).updating($drag) { value, state, _ in state = value.translation }.onEnded { pan.width += $0.translation.width; pan.height += $0.translation.height })
        .simultaneousGesture(MagnifyGesture().updating($magnification) { value, state, _ in state = value.magnification }.onEnded { zoom = min(12, max(0.2, zoom * $0.magnification)) })
        .simultaneousGesture(SpatialTapGesture().onEnded { value in
            let nearest = visible.min { hypot(point($0.id, size).x - value.location.x, point($0.id, size).y - value.location.y) < hypot(point($1.id, size).x - value.location.x, point($1.id, size).y - value.location.y) }
            if let node = nearest {
                let p = point(node.id, size)
                if hypot(p.x - value.location.x, p.y - value.location.y) < 28 { select(node) }
            }
        })
        .task(id: imageKey) {
            await thumbnails.load(visible, api: api)
        }
        .accessibilityLabel("Taste map, \(graph.nodes.count) nodes. Use search to select an idea or scene.")
    }
}

@MainActor @Observable private final class ThumbnailStore {
    var images: [String: Image] = [:]
    func load(_ visible: [GraphNode], api: APIClient) async {
        let nodes = visible.filter { $0.type == "scene" && images[$0.id] == nil }
        for start in stride(from: 0, to: nodes.count, by: 6) {
            if Task.isCancelled { return }
            await withTaskGroup(of: Void.self) { group in
                for node in nodes[start..<min(nodes.count, start + 6)] {
                    group.addTask { await self.loadOne(node, api: api) }
                }
            }
        }
    }
    private func loadOne(_ node: GraphNode, api: APIClient) async {
        guard !Task.isCancelled, let image = node.image, let request = api.imageRequest(image) else { return }
        if let loaded = await ImageCache.shared.load(request, api: api, maxPixel: 96) { images[node.id] = loaded }
    }
}
