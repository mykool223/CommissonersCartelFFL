import SwiftUI
import CartelCore

/// In-memory cache for team logos, keyed by URL.
///
/// Deliberately not `AsyncImage`: uploaded logos are served by the `espn-proxy`
/// function, which needs an `Authorization` header, and `AsyncImage` cannot set
/// one — Supabase rejects the request before the function runs.
actor LogoCache {
    static let shared = LogoCache()

    private var images: [URL: UIImage] = [:]
    /// URLs that failed. Retrying every time a row scrolls into view would
    /// hammer the proxy for logos that are never going to load.
    private var failed: Set<URL> = []

    func image(for url: URL, headers: [String: String]) async -> UIImage? {
        if let cached = images[url] { return cached }
        if failed.contains(url) { return nil }

        var request = URLRequest(url: url)
        for (field, value) in headers {
            request.setValue(value, forHTTPHeaderField: field)
        }

        guard let (data, response) = try? await URLSession.shared.data(for: request),
              let http = response as? HTTPURLResponse
        else {
            failed.insert(url)
            return nil
        }
        guard (200...299).contains(http.statusCode), let image = UIImage(data: data) else {
            // A refusal is about who was asking, not the logo: the proxy is
            // members only (#15), so after signing in the same URL loads.
            if ![401, 403].contains(http.statusCode) { failed.insert(url) }
            return nil
        }

        images[url] = image
        return image
    }
}

/// A team's logo, falling back to the league's own avatar.
///
/// The fallback is for a team with no logo, or one that failed to load. ESPN's
/// stock art is SVG, which `UIImage` cannot decode, so the proxy draws it as a
/// PNG (#16) and `ESPNMapper` points stock logos there.
///
/// The logo URL is re-read from ESPN on every launch and on pull-to-refresh, so
/// a manager who uploads an image simply has it appear next time the app is
/// opened — nothing is cached across launches.
struct TeamLogoView: View {
    let logoURL: URL?
    /// Shown only if the league avatar asset is somehow unavailable.
    let fallbackInitials: String
    var size: CGFloat = 40

    @Environment(AppEnvironment.self) private var environment
    @State private var image: UIImage?

    var body: some View {
        Group {
            if let image {
                circular(Image(uiImage: image))
            } else {
                circular(Image("DefaultTeamAvatar"))
            }
        }
        .task(id: logoURL) {
            guard let logoURL else {
                image = nil
                return
            }
            image = await LogoCache.shared.image(
                for: logoURL, headers: await environment.espnImageHeaders()
            )
        }
    }

    private func circular(_ image: Image) -> some View {
        image
            .resizable()
            .scaledToFill()
            .frame(width: size, height: size)
            .clipShape(.circle)
            .overlay {
                Circle().strokeBorder(Color.crestGoldShadow.opacity(0.35), lineWidth: 1)
            }
    }
}
