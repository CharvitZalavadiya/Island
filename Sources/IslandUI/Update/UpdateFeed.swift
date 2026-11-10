import Foundation
import IslandCore

/// Where Island asks what the newest version is. The real one asks GitHub; tests use a stand-in.
protocol UpdateFeed: Sendable {
    func latestRelease() async throws -> UpdateRelease
}

/// GitHub's "latest release" of the repository (it never answers with a draft or a pre-release). No account or token is
/// involved: it is the same public address anyone can open in a browser.
struct GitHubUpdateFeed: UpdateFeed {
    static let repository = "CharvitZalavadiya/Island"
    static let defaultURL = URL(string: "https://api.github.com/repos/\(repository)/releases/latest")!

    var url: URL = defaultURL
    var session: URLSession = URLSession(configuration: .ephemeral)

    func latestRelease() async throws -> UpdateRelease {
        var request = URLRequest(url: url)
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        request.setValue("Island/\(islandVersion)", forHTTPHeaderField: "User-Agent")
        request.timeoutInterval = 20
        let data: Data, response: URLResponse
        do {
            (data, response) = try await session.data(for: request)
        } catch {
            throw UpdateError.network(error.localizedDescription)
        }
        guard let http = response as? HTTPURLResponse else { throw UpdateError.unreadable }
        switch http.statusCode {
        case 200: return try UpdateDecoding.release(from: data)
        case 403, 429: throw UpdateError.rateLimited
        default: throw UpdateError.unreadable
        }
    }
}
