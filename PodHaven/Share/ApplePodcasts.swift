// Copyright Justin Bishop, 2025

import Foundation

struct ApplePodcasts {
  // MARK: - URL Analysis

  static func isPodcastURL(_ url: URL) -> Bool {
    // https://podcasts.apple.com/us/podcast/podcast-name/id1234567890
    url.scheme == "https" && url.host?.contains("podcasts.apple.com") == true
  }

  static func isEpisodeURL(_ url: URL) -> Bool {
    isPodcastURL(url) && url.query?.contains("i=") == true
  }

  // MARK: - Initialization

  private let session: DataFetchable
  private let url: URL

  init(session: DataFetchable, url: URL) {
    self.session = session
    self.url = url
  }

  // MARK: - Public Data Extraction

  func extractFeedURL() async throws(ShareError) -> FeedURL {
    let (url, request) = buildPodcastRequest(itunesID: try extractPodcastID())
    let lookupResult = try await parseItunesResponse(
      try await performRequest(url: url, request: request)
    )

    guard let feedURL = lookupResult.feedURL
    else { throw ShareError.noFeedURLFound }

    return feedURL
  }

  func extractEpisodeInfo() async throws(ShareError) -> (FeedURL, (MediaURL?, GUID?)) {
    let (url, request) = buildEpisodesRequest(podcastID: try extractPodcastID(), limit: 200)
    let lookupResult = try await parseItunesResponse(
      try await performRequest(url: url, request: request)
    )

    guard let feedURL = lookupResult.feedURL
    else { throw ShareError.noFeedURLFound }

    // Find the specific episode with matching ID
    let episodeID = try extractEpisodeID()
    guard
      let episodeInfo = lookupResult.results.first(where: { episode in
        episode.kind == "podcast-episode" && episode.trackId.map(String.init) == episodeID
      })
    else { return (feedURL, (nil, nil)) }

    return (feedURL, (episodeInfo.mediaURL, episodeInfo.guid))
  }

  // MARK: - Private URL Analysis

  private func extractPodcastID() throws(ShareError) -> String {
    let pathComponents = url.path.components(separatedBy: "/")
    for component in pathComponents {
      if component.hasPrefix("id"), component.count > 2 {
        let idString = String(component.dropFirst(2))
        if !idString.isEmpty { return idString }
      }
    }

    throw ShareError.noIdentifierFound(url)
  }

  private func extractEpisodeID() throws(ShareError) -> String {
    guard let components = URLComponents(url: url, resolvingAgainstBaseURL: false),
      let queryItems = components.queryItems,
      let episodeIDParam = queryItems.first(where: { $0.name == "i" })?.value,
      !episodeIDParam.isEmpty
    else { throw ShareError.noIdentifierFound(url) }

    return episodeIDParam
  }

  // MARK: - Private Parsing

  private struct ItunesTrackInfo: Decodable, Sendable {
    let kind: String?
    let trackId: Int?
    let episodeUrl: String?
    let episodeGuid: String?
    let feedUrl: String?

    var mediaURL: MediaURL? {
      guard let urlString = episodeUrl,
        let url = URL(string: urlString)
      else { return nil }
      return MediaURL(url)
    }

    var guid: GUID? {
      guard let guidString = episodeGuid
      else { return nil }
      return GUID(guidString)
    }
  }

  private struct ItunesLookupResult: Decodable, Sendable {
    let results: [ItunesTrackInfo]

    var feedURL: FeedURL? {
      guard let podcastInfo = results.first(where: { $0.kind == "podcast" }),
        let feedUrlString = podcastInfo.feedUrl,
        let url = URL(string: feedUrlString)
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

  // MARK: - Private Requesting

  private func performRequest(url: URL, request: URLRequest) async throws(ShareError) -> Data {
    do {
      return try await session.validatedData(for: request)
    } catch {
      throw ShareError.fetchFailure(request: request, caught: error)
    }
  }

  private func buildPodcastRequest(itunesID: String) -> (URL, URLRequest) {
    buildItunesRequest(queryItems: [
      URLQueryItem(name: "id", value: itunesID),
      URLQueryItem(name: "entity", value: "podcast"),
    ])
  }

  private func buildEpisodesRequest(podcastID: String, limit: Int = 200) -> (URL, URLRequest) {
    buildItunesRequest(queryItems: [
      URLQueryItem(name: "id", value: podcastID),
      URLQueryItem(name: "entity", value: "podcastEpisode"),
      URLQueryItem(name: "limit", value: String(limit)),
    ])
  }

  private func buildItunesRequest(queryItems: [URLQueryItem]) -> (URL, URLRequest) {
    var components = URLComponents()
    components.scheme = "https"
    components.host = "itunes.apple.com"
    components.path = "/lookup"
    components.queryItems = queryItems

    guard let url = components.url
    else { Assert.fatal("Can't make url from: \(components)?") }

    var request = URLRequest(url: url)
    request.httpMethod = "GET"
    request.addValue("PodHaven", forHTTPHeaderField: "User-Agent")

    return (url, request)
  }
}
