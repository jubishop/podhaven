// Copyright Justin Bishop, 2025

import FactoryKit
import Foundation
import Logging

extension Container {
  var shareServiceSession: Factory<DataFetchable> {
    Factory(self) {
      let configuration = URLSessionConfiguration.ephemeral
      configuration.allowsCellularAccess = true
      configuration.waitsForConnectivity = true
      let timeout = Double(10)
      configuration.timeoutIntervalForRequest = timeout
      configuration.timeoutIntervalForResource = timeout
      return URLSession(configuration: configuration)
    }
    .scope(.cached)
  }

  var shareService: Factory<ShareService> {
    Factory(self) { ShareService(session: self.shareServiceSession()) }.scope(.cached)
  }
}

actor ShareService {
  @LazyInjected(\.feedManager) private var feedManager
  @DynamicInjected(\.refreshManager) private var refreshManager

  private let session: DataFetchable

  // MARK: - Initialization

  fileprivate init(session: DataFetchable) {
    self.session = session
  }

  // MARK: - URL Handling

  func handleIncomingURL(_ sharedURL: URL, repo: any Databasing) async throws(ShareError) {
    let log = Log.as("ShareService")
    log.info("Received shared URL: \(sharedURL.absoluteString)")

    let extractedURL = try extractURLParameter(from: sharedURL)
    let urlType = SharedURLType.urlType(for: extractedURL)

    switch urlType {
    case .applePodcasts:
      try await handleApplePodcastsURL(extractedURL, repo: repo, log: log)
    case .unsupported:
      throw ShareError.unsupportedURL(extractedURL)
    }
  }

  private func extractURLParameter(from url: URL) throws(ShareError) -> URL {
    guard let components = URLComponents(url: url, resolvingAgainstBaseURL: false),
      let queryItems = components.queryItems,
      let urlParam = queryItems.first(where: { $0.name == "url" })?.value,
      let extractedURL = URL(string: urlParam)
    else {
      throw ShareError.extractionFailure(url)
    }
    return extractedURL
  }

  private func handleApplePodcastsURL(_ url: URL, repo: any Databasing, log: Logger)
    async throws(ShareError)
  {
    let itunesId = try ApplePodcasts.extractITunesID(from: url)
    log.info("Extracted iTunes ID: \(itunesId)")

    let lookupResult = try await lookupPodcastByItunesId(itunesId)

    guard let feedURL = lookupResult.feedURL else {
      log.error("No feed URL found for iTunes ID: \(itunesId)")
      throw ShareError.noFeedURLFound(itunesId)
    }

    log.info("Found feed URL: \(feedURL)")

    try await ShareError.catch {
      // Check if already subscribed
      if let podcastSeries = try await repo.podcastSeries(feedURL) {
        try await repo.markSubscribed(podcastSeries.id)
        try await refreshManager.refreshSeries(podcastSeries: podcastSeries)
        return
      }

      // Add new podcast using feedManager
      log.info("Adding new podcast from feed URL: \(feedURL)")

      let feedTask = await feedManager.addURL(feedURL)
      let podcastFeed: PodcastFeed
      do {
        podcastFeed = try await feedTask.feedParsed()
      } catch {
        log.error(error)
        throw error
      }

      let unsavedPodcast = try podcastFeed.toUnsavedPodcast(
        subscribed: true,
        lastUpdate: Date()
      )

      let newPodcastSeries = try await repo.insertSeries(
        unsavedPodcast,
        unsavedEpisodes: podcastFeed.episodes.compactMap { try? $0.toUnsavedEpisode() }
      )

      log.info(
        "Successfully added and subscribed to new podcast: \(newPodcastSeries.podcast.title)"
      )
    }
  }

  // MARK: - Apple Podcasts Integration

  func lookupPodcastByItunesId(_ itunesID: String) async throws(ShareError) -> ItunesLookupResult {
    try await Self.parseItunesResponse(
      try await performItunesRequest(itunesID: itunesID)
    )
  }

  // MARK: - Parsing

  static func parseItunesResponse(_ data: Data) async throws(ShareError) -> ItunesLookupResult {
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

  // MARK: - Private Helpers

  static private let baseHost = "itunes.apple.com"

  private func performItunesRequest(itunesID: String) async throws(ShareError) -> Data {
    let (url, request) = buildRequest(itunesID: itunesID)
    do {
      return try await DownloadError.catch {
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
    components.host = Self.baseHost
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
