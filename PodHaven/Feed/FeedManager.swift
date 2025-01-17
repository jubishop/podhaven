// Copyright Justin Bishop, 2025

import Factory
import Foundation

extension Container {
  var feedManager: Factory<FeedManager> {
    Factory(self) {
      let configuration = URLSessionConfiguration.ephemeral
      configuration.allowsCellularAccess = true
      configuration.waitsForConnectivity = true
      let timeout = Double(10)
      configuration.timeoutIntervalForRequest = timeout
      configuration.timeoutIntervalForResource = timeout
      return FeedManager(session: URLSession(configuration: configuration))
    }
    .scope(.singleton)
  }
}

typealias FeedResult = Result<PodcastFeed, any Error>

struct FeedTask: Sendable {
  let downloadTask: DownloadTask

  fileprivate init(_ downloadTask: DownloadTask) {
    self.downloadTask = downloadTask
  }

  func downloadBegan() async {
    await downloadTask.downloadBegan()
  }

  func feedParsed() async -> FeedResult {
    let downloadResult = await downloadTask.downloadFinished()
    switch downloadResult {
    case .failure:
      return .failure(Err.msg("Failed to load: \(downloadTask.url)"))
    case .success(let downloadData):
      do {
        let podcastFeed = try await PodcastFeed.parse(downloadData.data, from: downloadData.url)
        return .success(podcastFeed)
      } catch {
        return .failure(error)
      }
    }
  }

  func cancel() async {
    await downloadTask.cancel()
  }
}

final actor FeedManager: Sendable {
  // MARK: - Static Helpers

  static func refreshSeries(podcast: Podcast) async throws {
    let repo = Container.shared.repo()
    guard let podcastSeries = try await repo.podcastSeries(podcastID: podcast.id)
    else { return }

    try await refreshSeries(podcastSeries: podcastSeries)
  }

  static func refreshSeries(podcastSeries: PodcastSeries) async throws {
    let feedManager = Container.shared.feedManager()
    let feedTask = await feedManager.addURL(podcastSeries.podcast.feedURL)
    let feedResult = await feedTask.feedParsed()
    switch feedResult {
    case .failure(let error):
      throw error
    case .success(let podcastFeed):
      var newPodcast = try podcastFeed.toPodcast(mergingExisting: podcastSeries.podcast)
      var unsavedEpisodes: [UnsavedEpisode] = []
      var existingEpisodes: [Episode] = []
      for feedItem in podcastFeed.episodes {
        if let existingEpisode = podcastSeries.episodes[id: feedItem.guid] {
          if let newExistingEpisode = try? feedItem.toEpisode(
            mergingExisting: existingEpisode
          ) {
            existingEpisodes.append(newExistingEpisode)
          }
        } else if let newUnsavedEpisode = try? feedItem.toUnsavedEpisode() {
          unsavedEpisodes.append(newUnsavedEpisode)
        }
      }
      newPodcast.lastUpdate = Date()
      let repo = Container.shared.repo()
      try await repo.updateSeries(
        newPodcast,
        unsavedEpisodes: unsavedEpisodes,
        existingEpisodes: existingEpisodes
      )
    }
  }

  // MARK: - Concurrent Download Management

  private let downloadManager: DownloadManager
  private var feedTasks: [URL: FeedTask] = [:]
  private let asyncStream: AsyncStream<FeedResult>
  private let streamContinuation: AsyncStream<FeedResult>.Continuation

  var remainingFeeds: Int { feedTasks.count }

  fileprivate init(session: DataFetchable) {
    downloadManager = DownloadManager(session: session)
    (self.asyncStream, self.streamContinuation) = AsyncStream.makeStream(
      of: FeedResult.self
    )
  }

  deinit {
    streamContinuation.finish()
  }

  func feeds() -> AsyncStream<FeedResult> { asyncStream }

  @discardableResult
  func addURL(_ url: URL) async -> FeedTask {
    if let feedTask = feedTasks[url] { return feedTask }

    let feedTask = FeedTask(await downloadManager.addURL(url))
    feedTasks[url] = feedTask
    Task(priority: .utility) {
      let feedResult = await feedTask.feedParsed()
      streamContinuation.yield(feedResult)
      feedTasks.removeValue(forKey: url)
    }
    return feedTask
  }

  func cancelAll() async {
    for feedTask in feedTasks.values {
      await feedTask.cancel()
    }
    feedTasks.removeAll()
  }
}
