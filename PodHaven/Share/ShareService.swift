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
    } else if let (feedURL, (mediaURL, guid)) = try await extractEpisodeInfo(from: extractedURL) {
      try await handleEpisodeURL(feedURL: feedURL, mediaURL: mediaURL, guid: guid)
    } else if let feedURL = try await extractFeedURL(from: extractedURL) {
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

    await navigation.showPodcast(
      podcastSeries.podcast.subscribed ? .subscribed : .unsubscribed,
      podcastSeries.podcast
    )
  }

  private func handleOPMLURL(_ url: URL) async throws(ShareError) {
    Self.log.debug("handleOPMLURL: \(url)")

    try await ShareError.catch {
      let navigation = await self.navigation
      await navigation.showOPMLImport()

      let opmlViewModel = await Container.shared.opmlViewModel()
      await opmlViewModel.importOPMLFromURL(url: url)

      try FileManager.default.removeItem(at: url)
      Self.log.debug("Cleaned up shared OPML file: \(url)")
    }
  }

  private func handleEpisodeURL(feedURL: FeedURL, mediaURL: MediaURL?, guid: GUID?)
    async throws(ShareError)
  {
    Self.log.debug(
      """
      handleEpisodeURL:
          FeedURL: \(feedURL) 
          MediaURL: \(String(describing: mediaURL))
          GUID: \(String(describing: guid))
      """
    )

    try await ShareError.catch {
      let podcastSeries = try await findOrCreatePodcastSeries(feedURL: feedURL)

      if let matchingEpisode = await findMatchingEpisode(
        mediaURL: mediaURL,
        guid: guid,
        in: podcastSeries
      ) {
        Self.log.debug("handleEpisodeURL: Found matching episode: \(matchingEpisode.toString)")
        await navigation.showEpisode(
          podcastSeries.podcast.subscribed ? .subscribed : .unsubscribed,
          PodcastEpisode(podcast: podcastSeries.podcast, episode: matchingEpisode)
        )
      } else {
        Self.log.debug("handleEpisodeURL: Episode not found, showing podcast instead")
        await navigation.showPodcast(
          podcastSeries.podcast.subscribed ? .subscribed : .unsubscribed,
          podcastSeries.podcast
        )
      }
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
        await navigation.showPodcast(
          updatedPodcastSeries.podcast.subscribed ? .subscribed : .unsubscribed,
          updatedPodcastSeries.podcast
        )
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

  private func findMatchingEpisode(
    mediaURL: MediaURL?,
    guid: GUID?,
    in podcastSeries: PodcastSeries
  ) async -> Episode? {
    Self.log.debug(
      """
      findMatchingEpisode:
        MediaURL: \(String(describing: mediaURL))
        GUID: \(String(describing: guid))
        PodcastSeries: \(podcastSeries.toString)
      """
    )

    if let mediaURL {
      for episode in podcastSeries.episodes where episode.media == mediaURL {
        Self.log.debug("findMatchingEpisode: Found MediaURL match")
        return episode
      }
    }

    if let guid {
      for episode in podcastSeries.episodes where episode.guid == guid {
        Self.log.debug("findMatchingEpisode: Found GUID match")
        return episode
      }
    }

    Self.log.debug("findMatchingEpisode: No matching episode found")
    return nil
  }

  // MARK: - Online Data Fetching

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
