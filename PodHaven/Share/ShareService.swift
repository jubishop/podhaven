// Copyright Justin Bishop, 2025

import FactoryKit
import Foundation
import Logging
import Tagged

extension Container {
  var shareService: Factory<ShareService> {
    Factory(self) { ShareService() }.scope(.cached)
  }
}

struct ShareService {
  @DynamicInjected(\.iTunesService) private var iTunesService
  @DynamicInjected(\.repo) private var repo
  @DynamicInjected(\.refreshManager) private var refreshManager

  private var navigation: Navigation { get async { await Container.shared.navigation() } }

  private static let log = Log.as(LogSubsystem.ShareService.main)

  // MARK: - URL Analysis

  static func isShareURL(_ url: URL) -> Bool {
    url.host == "share"
  }

  // MARK: - URL Handling

  func handleIncomingURL(_ sharedURL: URL) async throws(ShareError) {
    Self.log.debug("handleIncomingURL: \(sharedURL)")

    let extractedURL = try extractURLParameter(from: sharedURL)
    Self.log.debug("extracted URL is: \(extractedURL)")

    if extractedURL.pathExtension.lowercased() == "opml" {
      try await handleOPMLURL(extractedURL)
    } else if let feedURL = extractFeedURLParameter(from: extractedURL) {
      try await handlePodcastURL(feedURL, guid: extractGUIDParameter(from: extractedURL))
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

  func handlePodcastURL(_ feedURL: FeedURL, guid: GUID? = nil) async throws(ShareError) {
    Self.log.debug("handlePodcastURL: \(feedURL), guid: \(guid?.toString ?? "nil")")

    try await ShareError.catch {
      if let podcastSeries = try await repo.podcastSeries(feedURL) {
        Self.log.debug(
          """
          Found existing podcast series
            FeedURL: \(feedURL)
            PodcastSeries: \(podcastSeries.toString)
          """
        )

        if let guid, let episode = podcastSeries.episodes.first(where: { $0.guid == guid }) {
          Self.log.debug("Found episode with guid: \(guid) - \(episode.toString)")
          await navigation.showEpisode(
            PodcastEpisode(podcast: podcastSeries.podcast, episode: episode)
          )
        } else {
          Self.log.debug("GUID: \(String(describing: guid)) not found, showing podcast")
          await navigation.showPodcast(podcastSeries.podcast)
        }
        return
      }

      Self.log.debug(
        """
        Fetching new podcast series
          FeedURL: \(feedURL)
        """
      )
      let podcastFeed: PodcastFeed = try await PodcastFeed.parse(feedURL)
      let unsavedPodcastSeries = try podcastFeed.toUnsavedSeries()
      if let guid,
        let unsavedEpisode = unsavedPodcastSeries.unsavedEpisodes.first(where: {
          $0.mediaGUID.guid == guid
        })
      {
        Self.log.debug("Found unsaved episode with guid: \(guid) - \(unsavedEpisode.toString)")

        await navigation.showSearchedEpisode(
          unsavedPodcastSeries: unsavedPodcastSeries,
          unsavedEpisode: unsavedEpisode
        )
      } else {
        Self.log.debug("GUID: \(String(describing: guid)) not found, showing unsaved podcast")
        await navigation.showSearchedUnsavedPodcastSeries(unsavedPodcastSeries)
      }
    }
  }

  private func handleOPMLURL(_ url: URL) async throws(ShareError) {
    Self.log.debug("handleOPMLURL: \(url)")

    try await ShareError.catch {
      let navigation = await self.navigation
      await navigation.showOPMLImport()

      let opmlViewModel = await OPMLViewModel()
      await opmlViewModel.importOPMLFromURL(url: url)

      try Container.shared.fileManager().removeItem(at: url)
      Self.log.debug("Cleaned up shared OPML file: \(url)")
    }
  }

  // MARK: - Private URL Analysis

  private func extractURLParameter(from url: URL) throws(ShareError) -> URL {
    guard let components = URLComponents(url: url, resolvingAgainstBaseURL: false),
      let queryItems = components.queryItems,
      let urlParam = queryItems.first(where: { $0.name == "url" })?.value,
      let extractedURL = URL(string: urlParam)
    else { throw ShareError.extractionFailure(url) }

    return extractedURL
  }

  private func extractFeedURLParameter(from url: URL) -> FeedURL? {
    guard let components = URLComponents(url: url, resolvingAgainstBaseURL: false),
      let queryItems = components.queryItems,
      let feedURLString = queryItems.first(where: { $0.name == "feedURL" })?.value,
      let feedURL = URL(string: feedURLString)
    else { return nil }

    return FeedURL(feedURL)
  }

  private func extractGUIDParameter(from url: URL) -> GUID? {
    guard let components = URLComponents(url: url, resolvingAgainstBaseURL: false),
      let queryItems = components.queryItems,
      let guidString = queryItems.first(where: { $0.name == "guid" })?.value
    else { return nil }

    return GUID(guidString)
  }

  // MARK: - Private Data Fetching

  private func fetchFeedURL(from url: URL) async throws(ShareError) -> FeedURL? {
    guard ITunesURL.isPodcastURL(url) else { return nil }

    Self.log.debug("trying to extract FeedURL from: \(url)")

    let podcastID = try ITunesURL.extractPodcastID(from: url)
    let podcastsWithMetadata = try await ShareError.catch {
      try await iTunesService.lookupPodcasts(podcastIDs: [podcastID])
    }

    guard let feedURL = podcastsWithMetadata.first?.feedURL
    else { throw ShareError.noFeedURLFound }

    return feedURL
  }
}
