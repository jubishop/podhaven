// Copyright Justin Bishop, 2025

import FactoryKit
import Foundation

struct ApplePodcasts {
  // MARK: - URL Analysis

  static func isApplePodcastsURL(_ url: URL) -> Bool {
    // https://podcasts.apple.com/us/podcast/podcast-name/id1234567890
    url.scheme == "https" && url.host?.contains("podcasts.apple.com") == true
  }

  // MARK: - Initialization

  private let session: DataFetchable
  private let url: URL

  init(session: DataFetchable, url: URL) {
    self.session = session
    self.url = url
  }

  // MARK: - FeedURLExtractable

  func extractFeedURL() async throws(ShareError) -> FeedURL {
    let itunesID = try extractITunesID()
    let lookupResult = try await lookupPodcastByItunesId(itunesID)

    guard let feedURL = lookupResult.feedURL
    else { throw ShareError.noFeedURLFound }

    return feedURL
  }

  // MARK: - Private Helpers

  private func extractITunesID() throws(ShareError) -> String {
    guard Self.isApplePodcastsURL(url)
    else { throw ShareError.unsupportedURL(url) }

    let pathComponents = url.path.components(separatedBy: "/")
    for component in pathComponents {
      if component.hasPrefix("id"), component.count > 2 {
        let idString = String(component.dropFirst(2))
        if !idString.isEmpty { return idString }
      }
    }

    throw ShareError.noIdentifierFound(url)
  }

  private func lookupPodcastByItunesId(_ itunesID: String) async throws(ShareError)
    -> ItunesLookupResult
  {
    try await parseItunesResponse(
      try await performItunesRequest(itunesID: itunesID)
    )
  }

  private struct ItunesLookupResult: Decodable, Sendable {
    struct PodcastInfo: Decodable, Sendable {
      let feedUrl: String?
    }

    let results: [PodcastInfo]
    var podcastInfo: PodcastInfo? { results.first }

    var feedURL: FeedURL? {
      guard let urlString = podcastInfo?.feedUrl,
        let url = URL(string: urlString)
      else { return nil }
      return FeedURL(url)
    }
  }

  private func parseItunesResponse(_ data: Data) async throws(ShareError) -> ItunesLookupResult {
    do {
      return try await withCheckedThrowingContinuation { continuation in
        let decoder = JSONDecoder()
        do {
          let result = try decoder.decode(ItunesLookupResult.self, from: data)
          continuation.resume(returning: result)
        } catch {
          continuation.resume(throwing: error)
        }
      }
    } catch {
      throw ShareError.parseFailure(data)
    }
  }

  private func performItunesRequest(itunesID: String) async throws(ShareError) -> Data {
    let (url, request) = buildRequest(itunesID: itunesID)
    do {
      return try await DownloadError.catch {
        let session = Container.shared.shareServiceSession()
        let (data, response) = try await session.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse else {
          throw DownloadError.notHTTPURLResponse(url)
        }
        guard (200...299).contains(httpResponse.statusCode) else {
          throw DownloadError.notOKResponseCode(code: httpResponse.statusCode, url: url)
        }
        return data
      }
    } catch {
      throw ShareError.fetchFailure(request: request, caught: error)
    }
  }

  private func buildRequest(itunesID: String) -> (URL, URLRequest) {
    var components = URLComponents()
    components.scheme = "https"
    components.host = "itunes.apple.com"
    components.path = "/lookup"
    components.queryItems = [
      URLQueryItem(name: "id", value: itunesID),
      URLQueryItem(name: "entity", value: "podcast"),
    ]

    guard let url = components.url
    else { Assert.fatal("Can't make url from: \(components)?") }

    var request = URLRequest(url: url)
    request.httpMethod = "GET"
    request.addValue("PodHaven", forHTTPHeaderField: "User-Agent")

    return (url, request)
  }
}
