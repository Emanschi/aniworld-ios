import SwiftUI
import UIKit
import AniworldKit

/// Thread-safe in-memory image cache.
final class ImageMemoryCache: @unchecked Sendable {
    static let shared = ImageMemoryCache()
    private let cache = NSCache<NSURL, UIImage>()

    init() { cache.countLimit = 300 }

    func image(for url: URL) -> UIImage? { cache.object(forKey: url as NSURL) }
    func store(_ image: UIImage, for url: URL) { cache.setObject(image, forKey: url as NSURL) }
}

/// Downloads images through URLSession (which uses the shared URLCache on disk).
actor ImageLoader {
    static let shared = ImageLoader()

    func load(_ url: URL) async -> UIImage? {
        if let cached = ImageMemoryCache.shared.image(for: url) { return cached }
        var request = URLRequest(url: url)
        request.cachePolicy = .returnCacheDataElseLoad
        guard let (data, _) = try? await URLSession.shared.data(for: request),
              let image = UIImage(data: data) else { return nil }
        let prepared = await image.byPreparingForDisplay() ?? image
        ImageMemoryCache.shared.store(prepared, for: url)
        return prepared
    }
}

/// Fills its container with a remote image (scaledToFill), fading in when loaded.
/// Shows nothing while loading; place it over a placeholder and clip it.
struct CachedImage: View {
    let url: URL?
    @State private var image: UIImage?

    init(url: URL?) {
        self.url = url
        let initial: UIImage? = url.flatMap { ImageMemoryCache.shared.image(for: $0) }
        _image = State(initialValue: initial)
    }

    var body: some View {
        ZStack {
            if let image {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFill()
                    .transition(.opacity)
            }
        }
        .task(id: url) { await load() }
    }

    private func load() async {
        guard let url else {
            image = nil
            return
        }
        if let cached = ImageMemoryCache.shared.image(for: url) {
            image = cached
            return
        }
        image = nil
        let loaded = await ImageLoader.shared.load(url)
        if Task.isCancelled { return }
        withAnimation(.easeOut(duration: 0.3)) { image = loaded }
    }
}

/// Gradient with the title's initials, shown when there is no cover (yet).
struct CoverPlaceholder: View {
    let title: String

    var body: some View {
        ZStack {
            Rectangle().fill(Theme.placeholderGradient(for: title))
            Text(Theme.initials(for: title))
                .font(.system(size: 34, weight: .heavy, design: .rounded))
                .foregroundStyle(.white.opacity(0.55))
                .minimumScaleFactor(0.4)
        }
    }
}

/// Rounded cover with placeholder. `aspect` is width / height.
struct CoverImage: View {
    let url: URL?
    let title: String
    var aspect: CGFloat = 2.0 / 3.0
    var cornerRadius: CGFloat = Theme.cardRadius

    var body: some View {
        Color.clear
            .aspectRatio(aspect, contentMode: .fit)
            .overlay {
                ZStack {
                    CoverPlaceholder(title: title)
                    CachedImage(url: url)
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .strokeBorder(Color.white.opacity(0.08), lineWidth: 1)
            )
    }
}

/// Cover of a series; fetches the cover lazily via `CoverProvider` when the summary has none.
struct SeriesCover: View {
    let series: SeriesSummary
    var aspect: CGFloat = 2.0 / 3.0
    var cornerRadius: CGFloat = Theme.cardRadius

    @Environment(\.aniworld) private var service
    @State private var fetched: URL?

    var body: some View {
        CoverImage(url: series.coverURL ?? fetched, title: series.title, aspect: aspect, cornerRadius: cornerRadius)
            .task(id: series.slug) {
                guard series.coverURL == nil, fetched == nil else { return }
                fetched = await CoverProvider.shared.coverURL(slug: series.slug, service: service)
            }
    }
}

/// Looks up cover URLs via `seriesDetail(slug:)` with an in-memory cache,
/// request de-duplication and limited concurrency.
actor CoverProvider {
    static let shared = CoverProvider()

    private let maxConcurrent = 3
    private var running = 0
    private var waiters: [CheckedContinuation<Void, Never>] = []
    private var found: [String: URL] = [:]
    private var failed: Set<String> = []
    private var inflight: [String: Task<URL?, Never>] = [:]

    func coverURL(slug: String, service: AniworldService) async -> URL? {
        if let url = found[slug] { return url }
        if failed.contains(slug) { return nil }
        if Task.isCancelled { return nil }
        if let task = inflight[slug] { return await task.value }
        let task = Task<URL?, Never> { await self.fetch(slug: slug, service: service) }
        inflight[slug] = task
        let result = await task.value
        inflight[slug] = nil
        return result
    }

    private func fetch(slug: String, service: AniworldService) async -> URL? {
        await acquire()
        let detail = try? await service.seriesDetail(slug: slug)
        release()
        if let url = detail?.coverURL ?? detail?.summary.coverURL {
            found[slug] = url
            return url
        }
        if detail != nil { failed.insert(slug) }
        return nil
    }

    private func acquire() async {
        if running < maxConcurrent {
            running += 1
            return
        }
        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            waiters.append(continuation)
        }
    }

    private func release() {
        if waiters.isEmpty {
            running -= 1
        } else {
            waiters.removeFirst().resume()
        }
    }
}
