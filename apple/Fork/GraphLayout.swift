import Foundation

// A spatial grid keeps the repulsion pass bounded for larger libraries.
// Layout work runs in a detached task; only the finished positions reach the UI.
actor GraphLayout {
    static let shared = GraphLayout()
    private var cache: [String: [String: CGPoint]] = [:]
    func positions(graph: Graph, key: String) async throws -> [String: CGPoint] {
        if let value = cache[key] { return value }
        let task = Task.detached(priority: .userInitiated) { try Self.compute(graph) }
        let result = try await withTaskCancellationHandler { try await task.value } onCancel: { task.cancel() }
        if cache.count >= 12 { cache.removeAll() }
        cache[key] = result
        return result
    }
    private struct Cell: Hashable { var x: Int; var y: Int }
    private static func compute(_ graph: Graph) throws -> [String: CGPoint] {
        let count = graph.nodes.count
        guard count > 0 else { return [:] }
        let indices = Dictionary(uniqueKeysWithValues: graph.nodes.enumerated().map { ($0.element.id, $0.offset) })
        let edges = graph.edges.compactMap { edge -> (Int, Int, Double)? in
            guard let a = indices[edge.source], let b = indices[edge.target] else { return nil }
            return (a, b, min(3, sqrt(edge.weight)))
        }
        var x = [Double](repeating: 0, count: count), y = x
        let radius = max(150, sqrt(Double(count)) * 24)
        for i in 0..<count {
            let angle = Double(i) * 2.399963229728653
            let distance = radius * sqrt(Double(i + 1) / Double(count))
            x[i] = cos(angle) * distance; y[i] = sin(angle) * distance
        }
        for iteration in 0..<300 {
            try Task.checkCancellation()
            var dx = [Double](repeating: 0, count: count), dy = dx
            var cells: [Cell: [Int]] = [:]
            let cellSize = 150.0
            for i in 0..<count { cells[Cell(x: Int(floor(x[i] / cellSize)), y: Int(floor(y[i] / cellSize))), default: []].append(i) }
            for i in 0..<count {
                let cell = Cell(x: Int(floor(x[i] / cellSize)), y: Int(floor(y[i] / cellSize)))
                for gx in (cell.x - 1)...(cell.x + 1) {
                    for gy in (cell.y - 1)...(cell.y + 1) {
                        for j in cells[Cell(x: gx, y: gy)] ?? [] where j > i {
                            let vx = x[i] - x[j], vy = y[i] - y[j]
                            let squared = max(16, vx * vx + vy * vy)
                            let force = 1500 / squared
                            dx[i] += vx * force; dy[i] += vy * force
                            dx[j] -= vx * force; dy[j] -= vy * force
                        }
                    }
                }
            }
            for (a, b, weight) in edges {
                let vx = x[b] - x[a], vy = y[b] - y[a]
                let distance = max(1, hypot(vx, vy))
                let spring = (distance - 72) * 0.012 * weight / distance
                dx[a] += vx * spring; dy[a] += vy * spring
                dx[b] -= vx * spring; dy[b] -= vy * spring
            }
            let temperature = 12 * (1 - Double(iteration) / 300) + 0.3
            for i in 0..<count {
                dx[i] -= x[i] * 0.003; dy[i] -= y[i] * 0.003
                let length = max(1, hypot(dx[i], dy[i]))
                let factor = min(temperature, length) / length
                x[i] += dx[i] * factor; y[i] += dy[i] * factor
            }
        }
        return Dictionary(uniqueKeysWithValues: graph.nodes.enumerated().map { ($0.element.id, CGPoint(x: x[$0.offset], y: y[$0.offset])) })
    }
}
