import SwiftUI
import ImageIO
#if os(iOS)
import UIKit
typealias PlatformImage = UIImage
#else
import AppKit
typealias PlatformImage = NSImage
#endif

@MainActor final class ImageCache {
    static let shared = ImageCache()
    private let cache = NSCache<NSString, PlatformImage>()
    private var pending: [String: Task<PlatformImage?, Never>] = [:]
    init() { cache.totalCostLimit = 80 * 1024 * 1024; cache.countLimit = 500 }
    func cached(_ key: String) -> Image? { cache.object(forKey: key as NSString).map(Self.image) }
    static func image(_ native: PlatformImage) -> Image {
        #if os(iOS)
        Image(uiImage: native)
        #else
        Image(nsImage: native)
        #endif
    }
    func load(_ request: URLRequest, api: APIClient, maxPixel: Int = 1600) async -> Image? {
        guard let url = request.url else { return nil }
        let key = "\(url.absoluteString)|\(maxPixel)"
        if let hit = cached(key) { return hit }
        if let task = pending[key] { return await task.value.map(Self.image) }
        let task = Task<PlatformImage?, Never> {
            do {
                let (data, response) = try await URLSession.shared.data(for: request)
                if (response as? HTTPURLResponse)?.statusCode == 401 { api.unauthorized = true }
                guard let response = response as? HTTPURLResponse, (200..<300).contains(response.statusCode) else { return nil }
                let cgImage = await Task.detached(priority: .utility) {
                    guard let source = CGImageSourceCreateWithData(data as CFData, nil) else { return nil as CGImage? }
                    return CGImageSourceCreateThumbnailAtIndex(source, 0, [
                        kCGImageSourceCreateThumbnailFromImageAlways: true,
                        kCGImageSourceCreateThumbnailWithTransform: true,
                        kCGImageSourceThumbnailMaxPixelSize: maxPixel
                    ] as CFDictionary)
                }.value
                guard let cgImage else { return nil }
                #if os(iOS)
                let native = UIImage(cgImage: cgImage)
                #else
                let native = NSImage(cgImage: cgImage, size: NSSize(width: cgImage.width, height: cgImage.height))
                #endif
                cache.setObject(native, forKey: key as NSString, cost: cgImage.bytesPerRow * cgImage.height)
                return native
            } catch { return nil }
        }
        pending[key] = task
        let value = await task.value
        pending[key] = nil
        return value.map(Self.image)
    }
}

struct RemoteImage: View {
    @Environment(APIClient.self) private var api
    var path: String?
    var fit = true
    var maxPixel = 1600
    @State private var image: Image?
    @State private var loading = false
    var body: some View {
        GeometryReader { proxy in
            ZStack {
                Rectangle().fill(.quaternary)
                if let image {
                    image.resizable().aspectRatio(contentMode: fit ? .fit : .fill)
                        .frame(width: proxy.size.width, height: proxy.size.height).clipped()
                } else if loading { ProgressView() }
                else { Image(systemName: "photo").foregroundStyle(.secondary) }
            }
        }
        .task(id: "\(api.server)|\(api.revision)|\(path ?? "")|\(maxPixel)") {
            image = nil
            guard let path, !path.isEmpty, let request = api.imageRequest(path) else { return }
            loading = true
            image = await ImageCache.shared.load(request, api: api, maxPixel: maxPixel)
            loading = false
        }
        .accessibilityLabel("Scene screenshot")
    }
}

struct ErrorNotice: View {
    var message: String
    var retry: () -> Void
    var body: some View {
        VStack(spacing: 12) {
            Label(message, systemImage: "exclamationmark.triangle").foregroundStyle(.secondary)
            Button("Try again", action: retry)
        }.padding().frame(maxWidth: .infinity)
    }
}
struct SceneCard: View {
    var scene: Scene
    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            RemoteImage(path: scene.image).frame(height: 140).clipShape(.rect(cornerRadius: 8))
            if let timestamp = scene.timestamp { Text(timestamp).font(.caption.monospacedDigit()).foregroundStyle(.secondary) }
            Text(scene.displayTitle).font(.subheadline).lineLimit(2)
        }.frame(maxWidth: .infinity, alignment: .leading).contentShape(Rectangle())
    }
}
func facetColor(_ facet: String?) -> Color {
    switch facet {
    case "technique": .blue
    case "style": .purple
    case "format": .orange
    case "motion": .green
    case "concepts": .teal
    default: .gray
    }
}
