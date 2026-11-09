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
  @DynamicInjected(\.fileManager) private var fileManager
  @DynamicInjected(\.iTunesService) private var iTunesService
  @DynamicInjected(\.repo) private var repo
  @DynamicInjected(\.refreshManager) private var refreshManager

  private var navigation: Navigation { get async { await Container.shared.navigation() } }

  private static let log = Log.as(LogSubsystem.ShareService.main)
  private static let sharedFilePrefix = "shared_file_"

  // MARK: - URL Analysis

  static func isShareURL(_ url: URL) -> Bool {
    url.host == "share" || ShareURL.universalLinkDestination(url) != nil
  }

  // MARK: - URL Handling

  func handleIncomingURL(_ sharedURL: URL) async throws {
    Self.log.debug("handleIncomingURL: \(sharedURL)")

    if let destination = ShareURL.universalLinkDestination(sharedURL) {
      try await handlePodcastURL(
        destination.feedURL,
        guid: destination.guid,
        startTime: destination.startTime
      )
      return
    }

    guard sharedURL.host == "share" else { throw URLError(.badURL) }

    guard let extractedURL = extractURLParameter(from: sharedURL) else {
      throw URLError(.badURL)
    }
    Self.log.debug("extracted URL is: \(extractedURL)")

    let queryItems = URLComponents(url: extractedURL, resolvingAgainstBaseURL: false)?.queryItems
    if extractedURL.isFileURL || extractedURL.pathExtension.lowercased() == "opml" {
      try await handleSharedFile(extractedURL)
    } else if queryItems?.contains(where: { $0.name == "feedURL" }) == true {
      guard let destination = ShareURL.universalLinkDestination(extractedURL)
      else { throw URLError(.unsupportedURL) }

      try await handlePodcastURL(
        destination.feedURL,
        guid: destination.guid,
        startTime: destination.startTime
      )
    } else if let feedURL = try await fetchFeedURL(from: extractedURL) {
      try await handlePodcastURL(feedURL)
    } else if let feedURL = ShareURL.validatedFeedURL(extractedURL.absoluteString) {
      try await handlePodcastURL(feedURL)
    } else {
      throw URLError(.unsupportedURL)
    }
  }

  func handlePodcastURL(_ feedURL: FeedURL, guid: GUID? = nil, startTime: Int? = nil) async throws {
    let feedURL = try feedURL.convertToHTTPSURL()
    Self.log.debug(
      """
      handlePodcastURL: \(feedURL), \
      guid: \(guid?.toString ?? "nil"), \
      startTime: \(String(describing: startTime))
      """
    )

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
          PodcastEpisode(podcast: podcastSeries.podcast, episode: episode),
          startTime: startTime
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

      await navigation.showSharedEpisode(
        unsavedPodcastSeries: unsavedPodcastSeries,
        unsavedEpisode: unsavedEpisode,
        startTime: startTime
      )
    } else {
      Self.log.debug("GUID: \(String(describing: guid)) not found, showing unsaved podcast")
      await navigation.showSharedUnsavedPodcastSeries(unsavedPodcastSeries)
    }
  }

  private func handleSharedFile(_ url: URL) async throws {
    Self.log.debug("handleSharedFile: \(url)")

    guard let fileURL = sharedFileURL(url) else { throw URLError(.unsupportedURL) }
    defer {
      do {
        try fileManager.removeItem(at: fileURL)
        Self.log.debug("Cleaned up shared file: \(fileURL)")
      } catch {
        Self.log.caughtError("handleSharedFile: failed to clean up shared file \(fileURL)", error)
      }
    }

    if fileURL.pathExtension.lowercased() != "opml" {
      let data = try await fileManager.readData(from: fileURL)
      guard await PodcastOPML.isOPML(data) else { throw URLError(.unsupportedURL) }
    }

    let navigation = await self.navigation
    await navigation.showOPMLImport()

    let opmlViewModel = await Container.shared.opmlViewModel()
    await opmlViewModel.importOPMLFromURL(url: fileURL)
  }

  private func sharedFileURL(_ url: URL) -> URL? {
    guard url.isFileURL,
      let container = fileManager.containerURL(
        forSecurityApplicationGroupIdentifier: AppInfo.appGroupID
      )
    else { return nil }

    let fileURL = URL(filePath: url.path(percentEncoded: false))
    guard fileURL.lastPathComponent.hasPrefix(Self.sharedFilePrefix),
      fileURL.deletingLastPathComponent().pathComponents == container.pathComponents
    else { return nil }

    return fileURL
  }

  // MARK: - Private URL Analysis

  private func extractURLParameter(from url: URL) -> URL? {
    guard let components = URLComponents(url: url, resolvingAgainstBaseURL: false),
      let queryItems = components.queryItems,
      let urlParam = queryItems.first(where: { $0.name == "url" })?.value,
      let extractedURL = URL(string: urlParam)
    else {
      Self.log.warning("Failed to extract url parameter from: \(url)")
      return nil
    }

    return extractedURL
  }

  // MARK: - Private Data Fetching

  private func fetchFeedURL(from url: URL) async throws -> FeedURL? {
    guard ITunesURL.isPodcastURL(url) else { return nil }

    Self.log.debug("trying to extract FeedURL from: \(url)")

    guard let podcastID = ITunesURL.extractPodcastID(from: url) else {
      return nil
    }
    let podcastsWithMetadata = try await iTunesService.lookupPodcasts(podcastIDs: [podcastID])

    guard let feedURL = podcastsWithMetadata.first?.feedURL else {
      Self.log.warning("Could not find a valid RSS feed for this podcast")
      return nil
    }

    return feedURL
  }
}
