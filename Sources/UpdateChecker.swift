import Foundation
import Combine

/// Checks GitHub Releases for a newer Claudette build and publishes an available
/// update so the menu can surface a quiet "update available" banner with a download
/// link. Deliberately passive — no popups, no nagging; discovery happens in the
/// widget area where the user is already looking.
@MainActor
final class UpdateChecker: ObservableObject {
    /// A newer release than the running build.
    struct Release: Equatable {
        let version: String   // normalized, e.g. "0.2.0"
        let url: URL          // the release page to send the user to
    }

    /// Set when GitHub advertises a version newer than ours; nil otherwise.
    @Published private(set) var available: Release?

    /// The running app's own version (CFBundleShortVersionString == MARKETING_VERSION).
    let currentVersion: String

    private let owner = "vfilby"
    private let repo = "Claudette"
    private let session: URLSession
    private var timer: Timer?

    /// Re-check a few times a day; releases are rare so this is plenty.
    private let interval: TimeInterval = 6 * 60 * 60

    init(currentVersion: String? = nil, session: URLSession = .shared) {
        self.currentVersion = currentVersion
            ?? (Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String)
            ?? "0.0.0"
        self.session = session
    }

    func start() {
        check()
        let t = Timer(timeInterval: interval, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.check() }
        }
        RunLoop.main.add(t, forMode: .common)
        timer = t
    }

    /// Hits the GitHub "latest release" endpoint and updates `available`. Network or
    /// parse failures are swallowed: a missed check just means no banner this round.
    func check() {
        guard let url = URL(string:
            "https://api.github.com/repos/\(owner)/\(repo)/releases/latest") else { return }
        // Snapshot immutables so the background completion never touches actor state.
        let current = currentVersion
        let fallback = URL(string: "https://github.com/\(owner)/\(repo)/releases/latest")

        var req = URLRequest(url: url)
        req.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        req.setValue("Claudette", forHTTPHeaderField: "User-Agent")

        let task = session.dataTask(with: req) { [weak self] data, _, _ in
            guard let data,
                  let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let tag = json["tag_name"] as? String else { return }

            let latest = Self.normalize(tag)
            let pageURL = (json["html_url"] as? String).flatMap(URL.init(string:)) ?? fallback

            Task { @MainActor in
                guard let self else { return }
                if Self.isNewer(latest, than: current), let pageURL {
                    self.available = Release(version: latest, url: pageURL)
                } else {
                    self.available = nil
                }
            }
        }
        task.resume()
    }

    // MARK: Version math

    /// Strips a leading "v"/"V" and whitespace from a tag like "v0.2.0".
    static func normalize(_ tag: String) -> String {
        var s = tag.trimmingCharacters(in: .whitespacesAndNewlines)
        if s.first == "v" || s.first == "V" { s.removeFirst() }
        return s
    }

    /// Numeric, component-wise semver compare. Missing components count as 0, and any
    /// pre-release/build suffix (after a "-") is ignored, so "0.2.0" > "0.1.9".
    static func isNewer(_ candidate: String, than current: String) -> Bool {
        let a = parts(candidate), b = parts(current)
        for i in 0..<max(a.count, b.count) {
            let x = i < a.count ? a[i] : 0
            let y = i < b.count ? b[i] : 0
            if x != y { return x > y }
        }
        return false
    }

    private static func parts(_ v: String) -> [Int] {
        let core = v.split(separator: "-").first.map(String.init) ?? v
        return core.split(separator: ".").map { Int($0) ?? 0 }
    }
}
