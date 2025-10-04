// Copyright Justin Bishop, 2025

import FactoryKit
import Foundation

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

struct ShareService {
  @DynamicInjected(\.feedManager) private var feedManager
  @DynamicInjected(\.repo) private var repo
  @DynamicInjected(\.refreshManager) private var refreshManager

  private var navigation: Navigation { get async { await Container.shared.navigation() } }

  private static let log = Log.as(LogSubsystem.ShareService.main)

  // MARK: - Initialization

  private let session: DataFetchable

  fileprivate init(session: DataFetchable) {
    self.session = session
  }

  // MARK: - URL Analysis

  static func isShareURL(_ url: URL) -> Bool {
    url.host == "share"
  }

  // MARK: - URL Handling

  func handleIncomingURL(_ sharedURL: URL) async throws(ShareError) {
    Self.log.debug("handleIncomingURL: \(sharedURL)")

    let extractedURL = try extractURLParameter(from: sharedURL)

    if extractedURL.pathExtension.lowercased() == "opml" {
      try await handleOPMLURL(extractedURL)
    } else if let feedURL = try await fetchFeedURL(from: extractedURL) {
      try await handlePodcastURL(feedURL)
    } else {  // Fallback to maybe this is just a pure FeedURL?
      do {
        try await handlePodcastURL(FeedURL(extractedURL))
      } catch {
        throw ShareError.unsupportedURL(extractedURL)
      }
    }
  }

  func handlePodcastURL(_ feedURL: FeedURL) async throws(ShareError) {
    Self.log.debug("handlePodcastURL: \(feedURL)")

    let podcastSeries = try await findOrCreatePodcastSeries(feedURL: feedURL)

    await navigation.showPodcast(podcastSeries.podcast)
  }

  private func handleOPMLURL(_ url: URL) async throws(ShareError) {
    Self.log.debug("handleOPMLURL: \(url)")

    try await ShareError.catch {
      let navigation = await self.navigation
      await navigation.showOPMLImport()

      let opmlViewModel = await Container.shared.opmlViewModel()
      await opmlViewModel.importOPMLFromURL(url: url)

      try Container.shared.podFileManager().removeItem(at: url)
      Self.log.debug("Cleaned up shared OPML file: \(url)")
    }
  }

  // MARK: - Database Querying

  private func findOrCreatePodcastSeries(feedURL: FeedURL) async throws(ShareError) -> PodcastSeries
  {
    try await ShareError.catch {
      if let podcastSeries = try await repo.podcastSeries(feedURL) {
        Self.log.debug(
          """
          findOrCreatePodcastSeries: Found existing podcast series
            FeedURL: \(feedURL)
            PodcastSeries: \(podcastSeries.toString)
          """
        )
        try await repo.markSubscribed(podcastSeries.id)
        try await refreshManager.refreshSeries(podcastSeries: podcastSeries)
        let updatedPodcastSeries = try await repo.podcastSeries(feedURL) ?? podcastSeries
        await navigation.showPodcast(updatedPodcastSeries.podcast)
        return updatedPodcastSeries
      }

      Self.log.debug("findOrCreatePodcastSeries: Adding new podcast from feed URL: \(feedURL)")
      let podcastFeed: PodcastFeed = try await feedManager.addURL(feedURL).feedParsed()
      return try await repo.insertSeries(
        try podcastFeed.toUnsavedPodcast(subscriptionDate: Date(), lastUpdate: Date()),
        unsavedEpisodes: podcastFeed.episodes.compactMap { try? $0.toUnsavedEpisode() }
      )
    }
  }

  // MARK: - URL Analysis

  private func extractURLParameter(from url: URL) throws(ShareError) -> URL {
    guard let components = URLComponents(url: url, resolvingAgainstBaseURL: false),
      let queryItems = components.queryItems,
      let urlParam = queryItems.first(where: { $0.name == "url" })?.value,
      let extractedURL = URL(string: urlParam)
    else { throw ShareError.extractionFailure(url) }

    return extractedURL
  }

  // MARK: - Online Data Fetching

  func fetchFeedURL(from url: URL) async throws(ShareError) -> FeedURL? {
    guard ITunesURL.isPodcastURL(url) else { return nil }

    Self.log.debug("trying to extract FeedURL from: \(url)")

    let podcastID = try ITunesURL.extractPodcastID(from: url)
    let request = ITunesURL.lookupRequest(podcastIDs: [podcastID])
    let lookupResult = try await decode(
      try await performRequest(request)
    )

    guard let feedURL = lookupResult.findPodcast(podcastID: podcastID)?.feedURL
    else { throw ShareError.noFeedURLFound }

    return feedURL
  }

  // MARK: - Private Helpers

  private func performRequest(_ request: URLRequest) async throws(ShareError) -> Data {
    do {
      return try await session.validatedData(for: request)
    } catch {
      throw ShareError.fetchFailure(request: request, caught: error)
    }
  }

  private func decode(_ data: Data) async throws(ShareError) -> ITunesEntityResults {
    do {
      return try JSONDecoder().decode(data)
    } catch {
      throw ShareError.parseFailure(data: data, caught: error)
    }
  }
}
