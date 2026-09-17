import CalmaKit
import Foundation

/// Optional, off-by-default check against GitHub Releases. The only network request Calma ever makes.
@MainActor
final class UpdateChecker: ObservableObject {
    static let enabledKey = "checkForUpdates"

    enum Result: Equatable {
        case idle
        case checking
        case upToDate
        case available(version: String, url: URL)
        case failed(String)
    }

    @Published private(set) var result: Result = .idle

    func checkNow() {
        result = .checking
        guard let url = URL(string: "https://api.github.com/repos/\(CalmaPaths.repository)/releases/latest") else { return }
        var request = URLRequest(url: url)
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        request.timeoutInterval = 10

        Task {
            do {
                let (data, _) = try await URLSession.shared.data(for: request)
                struct Release: Decodable {
                    let tagName: String
                    let htmlURL: String
                    enum CodingKeys: String, CodingKey { case tagName = "tag_name", htmlURL = "html_url" }
                }
                let release = try JSONDecoder().decode(Release.self, from: data)
                let latest = release.tagName.trimmingCharacters(in: CharacterSet(charactersIn: "vV"))
                if Self.isNewer(latest, than: CalmaVersion.current), let page = URL(string: release.htmlURL) {
                    result = .available(version: latest, url: page)
                } else {
                    result = .upToDate
                }
            } catch {
                result = .failed(error.localizedDescription)
            }
        }
    }

    static func isNewer(_ candidate: String, than current: String) -> Bool {
        let a = candidate.split(separator: ".").map { Int($0) ?? 0 }
        let b = current.split(separator: ".").map { Int($0) ?? 0 }
        for index in 0..<max(a.count, b.count) {
            let x = index < a.count ? a[index] : 0
            let y = index < b.count ? b[index] : 0
            if x != y { return x > y }
        }
        return false
    }
}
