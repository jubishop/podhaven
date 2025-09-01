// Copyright Justin Bishop, 2025

import FactoryKit
import Foundation

extension Container {
  var feedManagerSession: Factory<DataFetchable> {
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

  var feedDownloadManager: Factory<DownloadManager> {
    Factory(self) {
      DownloadManager(session: self.feedManagerSession())
    }
    .scope(.cached)
  }

  var feedManager: Factory<FeedManager> {
    Factory(self) { FeedManager(downloadManager: self.feedDownloadManager()) }.scope(.cached)
  }
}

typealias FeedResult = Result<PodcastFeed, FeedError>

struct FeedTask {
  let downloadTask: DownloadTask

  fileprivate init(_ downloadTask: DownloadTask) {
    self.downloadTask = downloadTask
  }

  func downloadBegan() async {
    await downloadTask.downloadBegan()
  }

  func feedParsed() async throws(FeedError) -> PodcastFeed {
    try await FeedError.catch {
      let downloadData = try await downloadTask.downloadFinished()
      return try await PodcastFeed.parse(
        downloadData.data,
        from: FeedURL(downloadData.url)
      )
    }
  }

  func cancel() async {
    await downloadTask.cancel()
  }
}

actor FeedManager {
  private static let log = Log.as(LogSubsystem.Feed.feedManager)

  // MARK: - Concurrent Download Management

  private let downloadManager: DownloadManager
  private var feedTasks: [FeedURL: FeedTask] = [:]

  var remainingFeeds: Int { feedTasks.count }

  fileprivate init(downloadManager: DownloadManager) {
    self.downloadManager = downloadManager
  }

  // MARK: - Downloading Feeds

  func hasURL(_ url: FeedURL) -> Bool { feedTasks[url] != nil }

  func addURL(_ url: FeedURL) async -> FeedTask {
    if let feedTask = feedTasks[url] { return feedTask }

    let feedTask = FeedTask(await downloadManager.addURL(url.rawValue))
    feedTasks[url] = feedTask

    Task { [weak self] in
      guard let self else { return }
      _ = try? await feedTask.feedParsed()
      await removeFeedTask(feedURL: url)
    }

    return feedTask
  }

  func cancelAll() async {
    for feedTask in feedTasks.values {
      await feedTask.cancel()
    }
    feedTasks.removeAll()
  }

  private func removeFeedTask(feedURL: FeedURL) {
    Self.log.trace("Removing feed task for \(feedURL)")

    feedTasks.removeValue(forKey: feedURL)
  }
}
