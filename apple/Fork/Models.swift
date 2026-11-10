import Foundation

struct Items<T: Decodable & Sendable>: Decodable, Sendable { var items: [T] }
struct Scene: Decodable, Identifiable, Sendable {
    var id: String
    var image: String?
    var timestamp: String?
    var title: String
    var link: String
    var description: String?
    var frame_urls: [String]?
    var t_start: Double?
    var t_end: Double?
    var tags: [String: [String]]?
    var source: Source?
    var displayTitle: String { title.isEmpty ? "Scene at \(timestamp ?? "0:00")" : title }
}
struct Source: Decodable, Identifiable, Sendable {
    var id: String
    var title: String
    var author: String
    var url: String
    var verdict: String?
    var scenes: [Scene]?
    var origin: String?
    var duration: Double?
    var pitch: String?
    var status: String?
    var platform: String?
    var displayTitle: String { title.isEmpty ? "Untitled source" : title }
}
struct TodayResponse: Decodable, Sendable {
    var day: String
    var total: Int
    var remaining: Int
    var items: [Source]
}
struct TagCount: Decodable, Identifiable, Sendable {
    var facet: String
    var tag: String
    var n: Int
    var id: String { "\(facet):\(tag)" }
}
struct Stats: Decodable, Sendable {
    var sources: Int
    var scenes: Int
    var tags: [TagCount]
}
struct HistoryItem: Decodable, Identifiable, Sendable {
    var id: String
    var title: String
    var author: String
    var url: String
    var verdict: String?
    var at: String?
    var cover: String?
    var date: Date? {
        guard let at else { return nil }
        let fractional = ISO8601DateFormatter()
        fractional.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return fractional.date(from: at) ?? ISO8601DateFormatter().date(from: at)
    }
}
struct GraphNode: Decodable, Identifiable, Sendable {
    var id: String
    var type: String
    var label: String
    var image: String?
    var timestamp: String?
    var link: String?
    var liked: Bool?
    var facet: String?
    var count: Int?
    var degree: Int
}
struct GraphEdge: Decodable, Sendable {
    var source: String
    var target: String
    var kind: String
    var weight: Double
    var cross: Bool?
    var shared: [String]?
}
struct Graph: Decodable, Sendable {
    var nodes: [GraphNode]
    var edges: [GraphEdge]
    var stats: [String: Int]
}
struct SwipeResponse: Decodable, Sendable { var id: String; var verdict: String }
struct ItemID: Identifiable, Hashable { var id: String }
