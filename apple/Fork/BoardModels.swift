import Foundation
import CoreGraphics

struct BoardsIndex: Decodable, Sendable {
    var accounts: [BoardAccount]
    var videos: [BoardVideo]
    // Creator seeds aren't boards until they have posts; the index displays accounts/videos.
}
struct BoardAccount: Decodable, Identifiable, Sendable {
    var id: String
    var handle: String
    var platform: String
    var sources: Int
    var scenes: Int
    var liked_scenes: Int
    var covers: [String]
    var profile: String?
}
struct BoardVideo: Decodable, Identifiable, Sendable {
    var id: String
    var source_id: String
    var title: String
    var author: String
    var platform: String
    var scenes: Int
    var note: String?
    var cover: String?
}
struct Board: Decodable, Sendable {
    var id: String
    var kind: String
    var title: String
    var subtitle: String
    var profile: String?
    var groups: [BoardGroup]
}
struct BoardGroup: Decodable, Identifiable, Sendable {
    var source_id: String
    var title: String
    var url: String
    var note: String?
    var verdict: String?
    var origin: String
    var scenes: [BoardScene]
    var id: String { source_id }
}
struct BoardScene: Decodable, Identifiable, Sendable {
    var id: String
    var image: String?
    var frames: [String]
    var timestamp: String?
    var displayTimestamp: String { timestamp ?? "0:00" }
    var title: String
    var link: String
    var tags: [String: [String]]
    var quality: Double?
}

// Geometry only: independent of SwiftUI and cheap to compute once per response.
struct BoardLayout {
    struct Frame: Identifiable {
        var group: BoardGroup
        var rect: CGRect
        var id: String { group.id }
        func cardRect(_ index: Int) -> CGRect {
            CGRect(x: rect.minX + 16 + CGFloat(index) * 196, y: rect.minY + 88, width: 180, height: 184)
        }
    }
    var frames: [Frame]
    var bounds: CGRect
    init(_ board: Board) {
        let widths = board.groups.map { max(360, CGFloat($0.scenes.count) * 196 + 16) }
        let area = widths.reduce(0, +) * 328
        let wrap = max(widths.max() ?? 360, sqrt(area) * 1.25)
        var x: CGFloat = 0, y: CGFloat = 0
        var result: [Frame] = []
        for (group, width) in zip(board.groups, widths) {
            if board.kind == "account", x > 0, x + width > wrap { x = 0; y += 328 }
            result.append(Frame(group: group, rect: CGRect(x: x, y: y, width: width, height: 288)))
            x += width + 40
        }
        frames = result
        bounds = result.reduce(CGRect.null) { $0.union($1.rect) }
        if bounds.isNull { bounds = CGRect(x: 0, y: 0, width: 360, height: 288) }
    }
}
