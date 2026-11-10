import Foundation

// Read-only integration checks. Compile with the same models/client as the app.
@main struct Smoke {
    @MainActor static func main() async throws {
        let api = APIClient()
        let stats: Stats = try await api.request("stats")
        let today: TodayResponse = try await api.request("today")
        let history: Items<HistoryItem> = try await api.request("history")
        print("Stats: \(stats.scenes) scenes, \(stats.sources) sources; Today: \(today.total); History: \(history.items.count)")
        let scenes: Items<Scene> = try await api.request("scenes", query: [.init(name: "limit", value: "60"), .init(name: "liked", value: "1")])
        guard let first = scenes.items.first else { fatalError("Expected a real Library scene") }
        let scene: Scene = try await api.request("scenes/\(first.id)")
        guard let sourceID = scene.source?.id, let image = scene.image, let request = api.imageRequest(image),
              let deepLink = URL(string: scene.link), ["http", "https"].contains(deepLink.scheme) else { fatalError("Missing scene detail fields") }
        let source: Source = try await api.request("sources/\(sourceID)")
        precondition(source.scenes?.contains { $0.id == scene.id } == true)
        let (imageData, response) = try await URLSession.shared.data(for: request)
        precondition((response as? HTTPURLResponse)?.statusCode == 200 && !imageData.isEmpty)
        let search: Items<Scene> = try await api.request("scenes", query: [.init(name: "q", value: "showreel"), .init(name: "limit", value: "60")])
        precondition(!search.items.isEmpty)
        if let tag = stats.tags.first {
            let filtered: Items<Scene> = try await api.request("scenes", query: [.init(name: "tag", value: tag.id)])
            precondition(filtered.items.allSatisfy { $0.tags?[tag.facet]?.contains(tag.tag) == true })
        }
        for mode in ["ideas", "full"] {
            let graph: Graph = try await api.request("graph", query: [.init(name: "mode", value: mode), .init(name: "liked", value: "1")])
            let ids = Set(graph.nodes.map(\.id))
            precondition(graph.edges.allSatisfy { ids.contains($0.source) && ids.contains($0.target) })
            let positions = try await GraphLayout.shared.positions(graph: graph, key: mode)
            precondition(positions.count == graph.nodes.count)
            if let idea = graph.nodes.first(where: { $0.type == "idea" }) {
                let focused: Graph = try await api.request("graph", query: [.init(name: "mode", value: mode), .init(name: "focus", value: idea.id), .init(name: "depth", value: "2")])
                precondition(focused.nodes.contains { $0.id == idea.id })
            }
            print("\(mode): \(graph.nodes.count) nodes, \(graph.edges.count) edges, focus decoded")
        }
        // Test the specified scale even when the current library is still being tagged.
        let nodes = (0..<900).map { GraphNode(id: "n\($0)", type: "idea", label: "Node \($0)", facet: "technique", degree: 9) }
        let edges = (0..<4000).map { GraphEdge(source: "n\($0 % 900)", target: "n\(($0 * 17 + 1) % 900)", kind: "co", weight: 1) }
        let graph = Graph(nodes: nodes, edges: edges, stats: [:])
        let clock = ContinuousClock()
        let start = clock.now
        let layout = try await GraphLayout.shared.positions(graph: graph, key: "scale-check")
        precondition(layout.count == 900 && layout.values.allSatisfy { $0.x.isFinite && $0.y.isFinite })
        print("900 nodes / 4000 edges / 300 iterations: \(start.duration(to: clock.now))")
        let cached = try await GraphLayout.shared.positions(graph: graph, key: "scale-check")
        precondition(cached.count == layout.count && layout.allSatisfy { cached[$0.key]?.x == $0.value.x && cached[$0.key]?.y == $0.value.y })
        let badAuth = APIClient()
        badAuth.token = "invalid-test-token"
        do {
            let _: Stats = try await badAuth.request("stats")
            fatalError("Expected 401")
        } catch APIError.http(401) { precondition(badAuth.unauthorized) }
        print("PASS: live decoding, Library search/tag, scene/source, image, Open-at URL, graph modes/focus/cache/scale, 401 banner state")
    }
}
