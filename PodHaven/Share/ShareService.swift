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

    if let (feedURL, (mediaURL, guid)) = try await extractEpisodeInfo(from: extractedURL) {
      try await handleEpisodeURL(feedURL: feedURL, mediaURL: mediaURL, guid: guid)
    } else if let feedURL = try await extractFeedURL(from: extractedURL) {
      try await handlePodcastURL(feedURL)
    } else {
      throw ShareError.unsupportedURL(extractedURL)
    }
  }

  private func handleEpisodeURL(feedURL: FeedURL, mediaURL: MediaURL?, guid: GUID?)
    async throws(ShareError)
  {
    log.debug(
      """
      handleEpisodeURL:
          FeedURL: \(feedURL) 
          MediaURL: \(String(describing: mediaURL))
          GUID: \(String(describing: guid))
      """
    )

    try await ShareError.catch {
      if let podcastSeries = try await repo.podcastSeries(feedURL) {
        try await refreshManager.refreshSeries(podcastSeries: podcastSeries)
        let updatedPodcastSeries = try await repo.podcastSeries(feedURL) ?? podcastSeries

        let matchingEpisode = try await findMatchingEpisode(
          mediaURL: mediaURL,
          guid: guid,
          in: updatedPodcastSeries
        )

        if let matchingEpisode = matchingEpisode {
          log.debug("handleEpisodeURL: Found matching episode: \(matchingEpisode.toString)")
          await navigation.showEpisode(
            updatedPodcastSeries.podcast.subscribed ? .subscribed : .unsubscribed,
            matchingEpisode
          )
        } else {
          log.debug("handleEpisodeURL: Episode not found, showing podcast instead")
          await navigation.showPodcast(
            updatedPodcastSeries.podcast.subscribed ? .subscribed : .unsubscribed,
            updatedPodcastSeries.podcast
          )
        }
        return
      }

      log.debug("handleEpisodeURL: Adding new podcast from episode URL")
      let podcastFeed: PodcastFeed = try await feedManager.addURL(feedURL).feedParsed()
      let newPodcastSeries = try await repo.insertSeries(
        try podcastFeed.toUnsavedPodcast(lastUpdate: Date()),
        unsavedEpisodes: podcastFeed.episodes.compactMap { try? $0.toUnsavedEpisode() }
      )

      let matchingEpisode = try await findMatchingEpisode(
        mediaURL: mediaURL,
        guid: guid,
        in: newPodcastSeries
      )

      if let matchingEpisode = matchingEpisode {
        log.debug(
          "handleEpisodeURL: Found matching episode in new podcast: \(matchingEpisode.toString)"
        )
        await navigation.showEpisode(
          newPodcastSeries.podcast.subscribed ? .subscribed : .unsubscribed,
          matchingEpisode
        )
      } else {
        log.debug("handleEpisodeURL: Episode not found in new podcast, showing podcast instead")
        await navigation.showPodcast(
          newPodcastSeries.podcast.subscribed ? .subscribed : .unsubscribed,
          newPodcastSeries.podcast
        )
      }

      log.info("Successfully processed episode URL for podcast: \(newPodcastSeries.toString)")
    }
  }

  private func handlePodcastURL(_ feedURL: FeedURL) async throws(ShareError) {
    log.debug("handlePodcastURL: FeedURL: \(feedURL)")

    try await ShareError.catch {
      let podcastSeries = try await findOrCreatePodcastSeries(feedURL: feedURL)

      await navigation.showPodcast(
        podcastSeries.podcast.subscribed ? .subscribed : .unsubscribed,
        podcastSeries.podcast
      )
    }
  }

  private func findOrCreatePodcastSeries(feedURL: FeedURL) async throws -> PodcastSeries {
    if let podcastSeries = try await repo.podcastSeries(feedURL) {
      log.debug(
        """
        findOrCreatePodcastSeries: Found existing podcast series
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
      return updatedPodcastSeries
    }

    log.debug("findOrCreatePodcastSeries: Adding new podcast from feed URL: \(feedURL)")
    let podcastFeed: PodcastFeed = try await feedManager.addURL(feedURL).feedParsed()
    let newPodcastSeries = try await repo.insertSeries(
      try podcastFeed.toUnsavedPodcast(lastUpdate: Date()),
      unsavedEpisodes: podcastFeed.episodes.compactMap { try? $0.toUnsavedEpisode() }
    )
    return newPodcastSeries
  }

  private func findMatchingEpisode(
    mediaURL: MediaURL?,
    guid: GUID?,
    in podcastSeries: PodcastSeries
  ) async throws -> PodcastEpisode? {
    //    // First try to match by mediaURL if available
    //    if let mediaURL = mediaURL {
    //      log.debug("findMatchingEpisode: Trying mediaURL match: \(mediaURL)")
    //      for episode in podcastSeries.episodes where episode.media == mediaURL {
    //        log.debug("findMatchingEpisode: Found direct mediaURL match")
    //        return episode
    //      }
    //    }
    //
    //    // Second: try GUID matching if available
    //    if let guid = guid {
    //      log.debug("findMatchingEpisode: Trying GUID match: \(guid)")
    //      for episode in podcastSeries.episodes where episode.guid == guid {
    //        log.debug("findMatchingEpisode: Found GUID match")
    //        return episode
    //      }
    //    }

    log.debug("findMatchingEpisode: No matching episode found")
    return nil
  }

  private func extractURLParameter(from url: URL) throws(ShareError) -> URL {
    guard let components = URLComponents(url: url, resolvingAgainstBaseURL: false),
      let queryItems = components.queryItems,
      let urlParam = queryItems.first(where: { $0.name == "url" })?.value,
      let extractedURL = URL(string: urlParam)
    else { throw ShareError.extractionFailure(url) }

    return extractedURL
  }

  private func extractEpisodeInfo(from url: URL) async throws(ShareError)
    -> (FeedURL, (MediaURL?, GUID?))?
  {
    if ApplePodcasts.isEpisodeURL(url) {
      return try await ApplePodcasts(session: session, url: url).extractEpisodeInfo()
    }

    return nil
  }

  private func extractFeedURL(from url: URL) async throws(ShareError) -> FeedURL? {
    if ApplePodcasts.isPodcastURL(url) {
      return try await ApplePodcasts(session: session, url: url).extractFeedURL()
    }

    return nil
  }
}
