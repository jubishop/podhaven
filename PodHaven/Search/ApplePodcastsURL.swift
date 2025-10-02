// Copyright Justin Bishop, 2025

import Foundation

struct ApplePodcastsURL {
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
    let request = buildPodcastRequest(itunesID: try extractPodcastID())
    let lookupResult = try await parseItunesResponse(
      try await performRequest(request)
    )

    guard let feedURL = lookupResult.feedURL
    else { throw ShareError.noFeedURLFound }

    return feedURL
  }

  func extractEpisodeInfo() async throws(ShareError) -> (FeedURL, (MediaURL?, GUID?)) {
    let request = buildEpisodesRequest(podcastID: try extractPodcastID(), limit: 200)
    let lookupResult = try await parseItunesResponse(
      try await performRequest(request)
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
      return try Self.decodeLookupResponse(data, as: ItunesLookupResult.self)
    } catch {
      throw ShareError.parseFailure(data)
    }
  }

  // MARK: - Private Requesting

  private func performRequest(_ request: URLRequest) async throws(ShareError) -> Data {
    do {
      return try await session.validatedData(for: request)
    } catch {
      throw ShareError.fetchFailure(request: request, caught: error)
    }
  }

  private func buildPodcastRequest(itunesID: String) -> URLRequest {
    Self.lookupRequest(
      ids: [itunesID],
      entity: "podcast"
    )
  }

  private func buildEpisodesRequest(podcastID: String, limit: Int = 200) -> URLRequest {
    Self.lookupRequest(
      ids: [podcastID],
      entity: "podcastEpisode",
      limit: limit
    )
  }

  // MARK: - Shared Helpers

  static func lookupRequest(
    ids: [String],
    entity: String,
    limit: Int? = nil,
    countryCode: String? = nil
  ) -> URLRequest {
    var queryItems: [URLQueryItem] = [
      URLQueryItem(name: "id", value: ids.joined(separator: ",")),
      URLQueryItem(name: "entity", value: entity),
    ]

    if let limit {
      queryItems.append(URLQueryItem(name: "limit", value: String(limit)))
    }

    if let countryCode {
      queryItems.append(URLQueryItem(name: "country", value: countryCode))
    }

    return lookupRequest(queryItems: queryItems)
  }

  static func lookupRequest(queryItems: [URLQueryItem]) -> URLRequest {
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
    return request
  }

  static func decodeLookupResponse<Response: Decodable>(
    _ data: Data,
    as type: Response.Type
  ) throws -> Response {
    try decoder.decode(type, from: data)
  }

  private static let decoder: JSONDecoder = {
    let decoder = JSONDecoder()
    decoder.keyDecodingStrategy = .useDefaultKeys
    return decoder
  }()
}
