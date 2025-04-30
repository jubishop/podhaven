// Copyright Justin Bishop, 2025

import ErrorKit
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
    .scope(.unique)
  }
}

typealias FeedResult = Result<PodcastFeed, FeedError>

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
    case .failure(let error):
      return .failure(FeedError.downloadFailure(error))
    case .success(let downloadData):
      do {
        let podcastFeed = try await PodcastFeed.parse(
          downloadData.data,
          from: FeedURL(downloadData.url)
        )
        return .success(podcastFeed)
      } catch let error as FeedError {
        return .failure(error)
      } catch {
        return .failure(FeedError.caught(error))
      }
    }
  }

  func cancel() async {
    await downloadTask.cancel()
  }
}

final actor FeedManager: Sendable {
  // MARK: - Static Helpers

  #if DEBUG
  static func initForTest(session: DataFetchable) -> FeedManager {
    FeedManager(session: session)
  }
  #endif

  // MARK: - Concurrent Download Management

  private let downloadManager: DownloadManager
  private let asyncStream: AsyncStream<FeedResult>
  private let streamContinuation: AsyncStream<FeedResult>.Continuation
  private var feedTasks: [FeedURL: FeedTask] = [:]

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

  // MARK: - Downloading Feeds

  @discardableResult
  func addURL(_ url: FeedURL) async -> FeedTask {
    if let feedTask = feedTasks[url] { return feedTask }

    let feedTask = FeedTask(await downloadManager.addURL(url.rawValue))
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
