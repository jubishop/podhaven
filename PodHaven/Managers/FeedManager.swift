// Copyright Justin Bishop, 2024

import Foundation

typealias FeedResult = Result<FeedData, FeedError>

struct FeedData: Sendable {
  let url: URL
  let feed: PodcastFeed
}

final actor FeedTask: Sendable {
  let downloadTask: DownloadTask
  var finished: Bool = false

  fileprivate init(_ downloadTask: DownloadTask) {
    self.downloadTask = downloadTask
  }

  func feedParsed() async -> FeedResult {
    defer { finished = true }
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
}

@globalActor
final actor FeedManager: Sendable {
  static let shared = FeedManager()

  private let downloadManager: DownloadManager
  private var feedTasks: [URL: FeedTask] = [:]

  private init() {
    let configuration = URLSessionConfiguration.ephemeral
    configuration.allowsCellularAccess = true
    configuration.waitsForConnectivity = true
    let timeout = Double(10)
    configuration.timeoutIntervalForRequest = timeout
    configuration.timeoutIntervalForResource = timeout
    downloadManager = DownloadManager(
      session: URLSession(configuration: configuration)
    )
  }

  func fetch(_ url: URL) async -> FeedTask {
    if let feedTask = feedTasks[url], !(await feedTask.finished) {
      return feedTask
    }
    let feedTask = FeedTask(await downloadManager.addURL(url))
    feedTasks[url] = feedTask
    return feedTask
  }
}
