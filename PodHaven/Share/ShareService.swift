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
  @DynamicInjected(\.repo) private var repo
  @DynamicInjected(\.refreshManager) private var refreshManager

  private var navigation: Navigation { get async { await Container.shared.navigation() } }

  private let log = Log.as(LogSubsystem.ShareService.main)

  // MARK: - Initialization

  private let session: DataFetchable

  fileprivate init(session: DataFetchable) {
    self.session = session
  }

  // MARK: - URL Handling

  static func isShareURL(_ url: URL) -> Bool {
    url.host == "share"
  }

  func handleIncomingURL(_ sharedURL: URL) async throws(ShareError) {
    log.debug("handleIncomingURL: Received shared URL: \(sharedURL)")

    let extractedURL = try extractURLParameter(from: sharedURL)
    let feedURL = try await extractFeedURL(from: extractedURL)

    log.debug("handleIncomingURL: Extracted feed URL: \(feedURL)")

    try await ShareError.catch {
      if let podcastSeries = try await repo.podcastSeries(feedURL) {
        log.debug(
          """
          handleIncomingURL: Found existing podcast series
            FeedURL: \(feedURL)
            PodcastSeries: \(podcastSeries.toString)
          """
        )
        try await refreshManager.refreshSeries(podcastSeries: podcastSeries)
        let updatedPodcastSeries = try await repo.podcastSeries(feedURL) ?? podcastSeries
        await navigation.showPodcast(
          updatedPodcastSeries.podcast.subscribed ? .subscribed : .unsubscribed,
          updatedPodcastSeries.podcast
        )
        return
      }

      log.debug("handleIncomingURL: Adding new podcast from feed URL: \(feedURL)")
      let podcastFeed: PodcastFeed = try await feedManager.addURL(feedURL).feedParsed()
      let newPodcastSeries = try await repo.insertSeries(
        try podcastFeed.toUnsavedPodcast(lastUpdate: Date()),
        unsavedEpisodes: podcastFeed.episodes.compactMap { try? $0.toUnsavedEpisode() }
      )

      await navigation.showPodcast(
        newPodcastSeries.podcast.subscribed ? .subscribed : .unsubscribed,
        newPodcastSeries.podcast
      )

      log.info("Successfully added new podcast: \(newPodcastSeries.toString)")
    }
  }

  private func extractURLParameter(from url: URL) throws(ShareError) -> URL {
    guard let components = URLComponents(url: url, resolvingAgainstBaseURL: false),
      let queryItems = components.queryItems,
      let urlParam = queryItems.first(where: { $0.name == "url" })?.value,
      let extractedURL = URL(string: urlParam)
    else { throw ShareError.extractionFailure(url) }

    return extractedURL
  }

  private func extractFeedURL(from url: URL) async throws(ShareError) -> FeedURL {
    if ApplePodcasts.isApplePodcastsURL(url) {
      return try await ApplePodcasts(session: session, url: url).extractFeedURL()
    }

    throw ShareError.unsupportedURL(url)
  }
}
