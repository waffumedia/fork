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
    // Stable across launches (Swift's Hasher is deliberately randomized).
    private static func discPosition(id: String, radius: Double) -> (Double, Double) {
        var state: UInt64 = 14695981039346656037
        for byte in id.utf8 { state = (state ^ UInt64(byte)) &* 1099511628211 }
        func uniform() -> Double {
            state &+= 0x9E3779B97F4A7C15
            var value = state
            value = (value ^ (value >> 30)) &* 0xBF58476D1CE4E5B9
            value = (value ^ (value >> 27)) &* 0x94D049BB133111EB
            value ^= value >> 31
            return Double(value >> 11) / 9007199254740992
        }
        let angle = uniform() * 2 * Double.pi
        let distance = radius * sqrt(uniform())
        return (cos(angle) * distance, sin(angle) * distance)
    }
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
            (x[i], y[i]) = discPosition(id: graph.nodes[i].id, radius: radius)
        }
        let iterations = 1000
        let cellSize = 120.0
        let reach = 360.0
        let cellReach = Int(ceil(reach / cellSize))
        for iteration in 0..<iterations {
            try Task.checkCancellation()
            var dx = [Double](repeating: 0, count: count), dy = dx
            var cells: [Cell: [Int]] = [:]
            for i in 0..<count { cells[Cell(x: Int(floor(x[i] / cellSize)), y: Int(floor(y[i] / cellSize))), default: []].append(i) }
            for i in 0..<count {
                let cell = Cell(x: Int(floor(x[i] / cellSize)), y: Int(floor(y[i] / cellSize)))
                // Visit every cell intersecting the circular neighbourhood. Cell
                // membership never defines the force or its cutoff.
                for gx in (cell.x - cellReach)...(cell.x + cellReach) {
                    for gy in (cell.y - cellReach)...(cell.y + cellReach) {
                        for j in cells[Cell(x: gx, y: gy)] ?? [] where j > i {
                            let vx = x[i] - x[j], vy = y[i] - y[j]
                            let squared = vx * vx + vy * vy
                            guard squared < reach * reach else { continue }
                            // Smoothly vanish at the radius to avoid boundary ridges.
                            let taper = 1 - squared / (reach * reach)
                            let force = 2400 * taper * taper / max(1, squared)
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
            let temperature = 18 * pow(1 - Double(iteration) / Double(iterations), 2) + 0.02
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
