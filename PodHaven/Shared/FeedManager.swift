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

  private let downloadManager: DownloadManager
  private var feedTasks: [URL: FeedTask] = [:]

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
  }

  func addURL(_ url: URL) async -> FeedTask {
    if let feedTask = feedTasks[url] { return feedTask }

    let feedTask = FeedTask(await downloadManager.addURL(url))
    feedTasks[url] = feedTask
    Task(priority: .utility) {
      _ = await feedTask.feedParsed()
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
