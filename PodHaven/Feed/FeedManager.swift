// Copyright Justin Bishop, 2024

import Foundation

typealias FeedResult = Result<FeedData, FeedError>

struct FeedData: Sendable {
  let url: URL
  let feed: PodcastFeed
}

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
      return .failure(.failedLoad(downloadTask.url))
    case .success(let downloadData):
      let parseResult = await PodcastFeed.parse(downloadData.data)
      switch parseResult {
      case .success(let feed):
        return .success(FeedData(url: downloadTask.url, feed: feed))
      case .failure(let error):
        return .failure(error)
      }
    }
  }

  func cancel() async {
    await downloadTask.cancel()
  }
}

final actor FeedManager: Sendable {
  static let shared = FeedManager()

  // MARK: - Static Helpers

  static func refreshSeries(podcastSeries: PodcastSeries) async throws {
    let feedTask = await shared.addURL(podcastSeries.podcast.feedURL)
    let feedResult = await feedTask.feedParsed()
    switch feedResult {
    case .failure(let error):
      throw error
    case .success(let feedData):
      guard
        var newPodcast = feedData.feed.toPodcast(
          mergingExisting: podcastSeries.podcast
        )
      else {
        throw FeedError.failedParse(
          "Failed to refresh series: \(podcastSeries.podcast.toString)"
        )
      }
      var unsavedEpisodes: [UnsavedEpisode] = []
      var existingEpisodes: [Episode] = []
      for feedItem in feedData.feed.items {
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
      try await Repo.shared.updateSeries(
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

  init(maxConcurrentDownloads: Int = 8) {
    let configuration = URLSessionConfiguration.ephemeral
    configuration.allowsCellularAccess = true
    configuration.waitsForConnectivity = true
    let timeout = Double(10)
    configuration.timeoutIntervalForRequest = timeout
    configuration.timeoutIntervalForResource = timeout
    downloadManager = DownloadManager(
      session: URLSession(configuration: configuration),
      maxConcurrentDownloads: maxConcurrentDownloads
    )
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
