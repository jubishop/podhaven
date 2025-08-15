// Copyright Justin Bishop, 2025

import AVFoundation
import FactoryKit
import Foundation
import IdentifiedCollections

extension Container {
  var podcastFeedSession: Factory<DataFetchable> {
    Factory(self) { URLSession.shared }.scope(.cached)
  }
}

struct EpisodeFeed: Sendable, Equatable {
  let guid: GUID
  let media: MediaURL

  private let rssEpisode: PodcastRSS.Episode

  fileprivate init(rssEpisode: PodcastRSS.Episode) throws(ParseError) {
    guard let mediaURL = rssEpisode.enclosure?.url
    else { throw ParseError.missingMediaURL(rssEpisode.title) }

    let validatedMediaURL: MediaURL
    do {
      validatedMediaURL = MediaURL(try mediaURL.rawValue.convertToValidURL())
    } catch {
      throw ParseError.invalidMediaURL(mediaURL)
    }

    self.rssEpisode = rssEpisode
    self.guid = rssEpisode.guid ?? GUID(validatedMediaURL.absoluteString)
    self.media = validatedMediaURL
  }

  func toUnsavedEpisode(merging episode: Episode? = nil) throws(FeedError) -> UnsavedEpisode {
    Assert.precondition(
      episode == nil || (episode?.guid == guid || episode?.media == media),
      """
      Merging two episodes with different guids and media URLs?:
        GUIDs: \(String(describing: episode?.guid)), \(guid)
        Media URLs: \(String(describing: episode?.media)), \(media)
      """
    )

    return try FeedError.catch {
      try UnsavedEpisode(
        podcastId: episode?.podcastId,
        guid: guid,
        media: media,
        title: rssEpisode.title,
        pubDate: rssEpisode.pubDate ?? episode?.pubDate,
        duration: duration ?? episode?.duration,
        description: rssEpisode.description ?? episode?.description,
        link: rssEpisode.link ?? episode?.link,
        image: rssEpisode.iTunes.image?.href ?? episode?.image,
        completionDate: episode?.completionDate,
        currentTime: episode?.currentTime,
        queueOrder: episode?.queueOrder
      )
    }
  }

  // MARK: - Private Helpers

  private var duration: CMTime? {
    guard let timeComponents = rssEpisode.iTunes.duration?.split(separator: ":"),
      timeComponents.count <= 3
    else { return nil }

    var seconds = 0
    var multiplier = 1
    for value in timeComponents.reversed() {
      guard let value = Int(value) else { return nil }
      seconds += multiplier * value
      multiplier *= 60
    }
    return CMTime.seconds(Double(seconds))
  }

  // MARK: - Equatable

  static func == (lhs: EpisodeFeed, rhs: EpisodeFeed) -> Bool {
    lhs.guid == rhs.guid
  }
}

struct PodcastFeed: Sendable, Stringable {
  private static let log = Log.as(LogSubsystem.Feed.podcast)

  // MARK: - Static Parsing Methods

  static func parse(_ url: FeedURL) async throws(FeedError) -> PodcastFeed {
    try await FeedError.catch {
      let data = try await Container.shared.podcastFeedSession().validatedData(from: url.rawValue)
      return try await parse(data, from: url)
    }
  }

  static func parse(_ data: Data, from: FeedURL) async throws(FeedError) -> PodcastFeed {
    do {
      log.trace("Parsing data of size \(data.count) from \(from)")

      let rssPodcast = try await PodcastRSS.parse(data)
      return try PodcastFeed(rssPodcast: rssPodcast, from: from)
    } catch {
      throw FeedError.parseFailure(url: from, caught: error)
    }
  }

  // MARK: - Instance Definition

  let episodes: [EpisodeFeed]

  let feedURL: FeedURL
  private let rssPodcast: PodcastRSS.Podcast
  private let link: URL?
  private let image: URL

  private init(rssPodcast: PodcastRSS.Podcast, from: FeedURL) throws {
    self.rssPodcast = rssPodcast
    self.feedURL = FeedURL(try (rssPodcast.feedURL ?? from).rawValue.convertToValidURL())
    self.link = rssPodcast.link
    self.image = rssPodcast.iTunes.image.href
    self.episodes = rssPodcast.episodes.compactMap { rssEpisode in
      do {
        return try EpisodeFeed(rssEpisode: rssEpisode)
      } catch {
        Self.log.error(error)
        return nil
      }
    }
  }

  var updatedFeedURL: FeedURL {
    rssPodcast.iTunes.newFeedURL ?? feedURL
  }

  func toUnsavedPodcast(subscriptionDate: Date? = nil, lastUpdate: Date? = nil) throws(FeedError)
    -> UnsavedPodcast
  {
    try FeedError.catch {
      try UnsavedPodcast(
        feedURL: updatedFeedURL,
        title: rssPodcast.title,
        image: image,
        description: rssPodcast.description,
        link: link,
        lastUpdate: lastUpdate,
        subscriptionDate: subscriptionDate
      )
    }
  }

  func toUnsavedPodcast(merging unsavedPodcast: UnsavedPodcast) throws(FeedError) -> UnsavedPodcast
  {
    Assert.precondition(
      unsavedPodcast.feedURL == feedURL || unsavedPodcast.feedURL == updatedFeedURL,
      """
      Merging two podcasts with different feedURLs?:
        \(feedURL) != \(unsavedPodcast.feedURL) and
        \(updatedFeedURL) != \(unsavedPodcast.feedURL)
      """
    )

    return try toUnsavedPodcast(
      subscriptionDate: unsavedPodcast.subscriptionDate,
      lastUpdate: unsavedPodcast.lastUpdate
    )
  }

  func toEpisodeArray(merging podcastSeries: PodcastSeries? = nil)
    -> IdentifiedArray<GUID, UnsavedEpisode>
  {
    let allEpisodes = episodes.compactMap { episodeFeed in
      try? episodeFeed.toUnsavedEpisode(
        merging: podcastSeries?.episodes[id: episodeFeed.guid]
      )
    }

    var seenGUIDs: [GUID: UnsavedEpisode] = Dictionary(capacity: allEpisodes.count)
    var seenMediaURLs: [MediaURL: UnsavedEpisode] = Dictionary(capacity: allEpisodes.count)

    for episode in allEpisodes {
      // Check GUID conflict
      if let existingByGUID = seenGUIDs[episode.guid] {
        guard episode.pubDate >= existingByGUID.pubDate
        else { continue }

        // Remove the old one from media URLs
        seenMediaURLs.removeValue(forKey: existingByGUID.media)
      }

      // Check media URL conflict
      if let existingByMedia = seenMediaURLs[episode.media] {
        guard episode.pubDate >= existingByMedia.pubDate
        else { continue }

        // Remove the old one from GUIDs
        seenGUIDs.removeValue(forKey: existingByMedia.guid)
      }

      seenGUIDs[episode.guid] = episode
      seenMediaURLs[episode.media] = episode
    }

    return IdentifiedArray(uniqueElements: seenGUIDs.values, id: \.guid)
  }

  // MARK: - Stringable

  var toString: String { "(\(updatedFeedURL.toString)) - \(rssPodcast.title)" }

  // MARK: - Hashable

  func hash(into hasher: inout Hasher) {
    hasher.combine(updatedFeedURL)
  }

  // MARK: - Equatable

  static func == (lhs: PodcastFeed, rhs: PodcastFeed) -> Bool {
    lhs.updatedFeedURL == rhs.updatedFeedURL
  }
}
