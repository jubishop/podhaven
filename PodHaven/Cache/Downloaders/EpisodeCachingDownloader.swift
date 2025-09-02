// Copyright Justin Bishop, 2025

import FactoryKit
import Foundation

// MARK: - EpisodeCachingDownloader

protocol EpisodeCachingDownloader: Sendable {
  @discardableResult
  func start(_ podcastEpisode: PodcastEpisode) async throws(CacheError) -> Bool
}

// MARK: - Background (Production) implementation

struct BackgroundCacheDownloader: EpisodeCachingDownloader, Sendable {
  @DynamicInjected(\.imageFetcher) private var imageFetcher

  func start(_ podcastEpisode: PodcastEpisode) async throws(CacheError) -> Bool {
    // If already cached, no work
    guard podcastEpisode.episode.cachedFilename == nil else { return false }

    // Prefetch artwork up-front
    await imageFetcher.prefetch([podcastEpisode.image])

    // Schedule background download via harness
    var request = URLRequest(url: podcastEpisode.episode.media.rawValue)
    request.allowsExpensiveNetworkAccess = true
    request.allowsConstrainedNetworkAccess = true

    let bgFetch: any DataFetchable = Container.shared.cacheBackgroundFetchable()
    let taskID = await bgFetch.scheduleDownload(request)

    let cacheState: CacheState = await Container.shared.cacheState()
    await cacheState.setDownloadTaskIdentifier(podcastEpisode.id, taskIdentifier: taskID)

    let mg = MediaGUID(guid: podcastEpisode.episode.guid, media: podcastEpisode.episode.media)
    let taskMap = Container.shared.cacheTaskMapStore()
    await taskMap.set(taskID: taskID, for: mg)

    return true
  }
}

// MARK: - DI

extension Container {
  var cacheEpisodeDownloader: Factory<any EpisodeCachingDownloader> {
    Factory(self) { BackgroundCacheDownloader() }.scope(.cached)
  }

  // Fetchable that points at the background session in prod, and a fake in tests
  var cacheBackgroundFetchable: Factory<any DataFetchable> {
    Factory(self) { self.cacheBackgroundSession() as any DataFetchable }
      .context(.test) { FakeDataFetchable() }
      .scope(.cached)
  }
}
