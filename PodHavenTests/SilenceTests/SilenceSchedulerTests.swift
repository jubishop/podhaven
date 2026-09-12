// Copyright Justin Bishop, 2026

import FactoryKit
import Foundation
import Testing

@testable import PodHaven

private final class SilenceSchedulerBundle: NSObject {}

@Suite("Silence analysis scheduling", .container)
struct SilenceSchedulerTests {
  private let identifier = "\(AppInfo.bundleIdentifier).silenceAnalysis"

  private func cache(
    _ episode: PodcastEpisode,
    playable: Bool,
    fixtureName: String = "silence-mono-vbr"
  ) async throws -> URL {
    let task = try await CacheHelpers.downloadToCache(episode.id)
    try await CacheHelpers.simulateBackgroundFinish(task)
    let url = try await CacheHelpers.waitForCached(episode.id).rawValue
    if playable {
      let fixture = try #require(
        Bundle(for: SilenceSchedulerBundle.self)
          .url(forResource: fixtureName, withExtension: "mp3")
      )
      try FileManager.default.createDirectory(
        at: url.deletingLastPathComponent(),
        withIntermediateDirectories: true
      )
      try FileManager.default.copyItem(at: fixture, to: url)
    }
    return url
  }

  @Test(
    "foreground analysis requests background priority and applies the injected priority",
    .timeLimit(.minutes(5)),
    arguments: [TaskPriority.background, .high]
  )
  func foregroundTaskPriority(priority: TaskPriority) async throws {
    let episode = try await Create.podcastEpisode()
    let url = try await cache(episode, playable: true, fixtureName: "silence-priority")
    defer { try? FileManager.default.removeItem(at: url) }
    Container.shared.userSettings().$silenceMode.new(.balanced)
    let scheduler = Container.shared.bgTaskScheduler() as! FakeBGTaskScheduler
    let processor = Container.shared.silenceProcessor()
    processor.register()
    defer { processor.handleScenePhaseChange(to: .background) }
    try await Wait.until(maxAttempts: 200) {
      scheduler.pendingIdentifiers.contains(identifier)
    } _: {
      "No eligible silence work was observed"
    }
    let requests = ThreadSafe<[TaskPriority?]>([])
    Container.shared.taskPriority
      .context(.test) {
        { requested in
          requests { $0.append(requested) }
          return priority
        }
      }
      .reset(.scope)
    let analysisFinished = AsyncLatch<LogCapture.Captured>()
    let completed = try await LogCapture.withSink(
      onCapture: { entry in
        if entry.message.contains("Silence analysis file=") { analysisFinished.open(entry) }
      }
    ) { _ in
      processor.handleScenePhaseChange(to: .active)
      return try await analysisFinished.wait()
    }
    #expect(!requests().isEmpty)
    #expect(requests().allSatisfy { $0 == .background })
    #expect(completed.taskBasePriority == priority)
    #expect(completed.message.contains("published=true"))
    #expect(
      try await Container.shared.silenceStore().content(for: url.lastPathComponent)?.map != nil
    )
  }

  @Test(
    "a background grant prepares current, queued, and other downloads in order",
    .timeLimit(.minutes(5))
  )
  func priority() async throws {
    let other = try await Create.podcastEpisode()
    let queued = try await Create.podcastEpisode(Create.unsavedEpisode(queueOrder: 0))
    let current = try await Create.podcastEpisode()
    var urls: [URL] = []
    defer { for url in urls { try? FileManager.default.removeItem(at: url) } }
    for episode in [other, queued, current] {
      urls.append(try await cache(episode, playable: true))
    }
    Container.shared.sharedState().currentEpisodeID = current.id
    Container.shared.userSettings().$silenceMode.new(.balanced)
    let scheduler = Container.shared.bgTaskScheduler() as! FakeBGTaskScheduler
    let captured = try await LogCapture.withSink { sink in
      Container.shared.silenceProcessor().register()
      try await Wait.until(maxAttempts: 200) {
        scheduler.pendingIdentifiers.contains(identifier)
      } _: {
        "No background work was requested"
      }
      let task = try #require(scheduler.launchTask(withIdentifier: identifier))
      defer { task.expire() }
      try await task.completed.wait()
      #expect(task.completionResults == [true])
      return sink.captured().filter { $0.message.contains("Silence analysis file=") }
    }
    #expect(captured.count == 3)
    for (entry, url) in zip(captured, urls.reversed()) {
      #expect(entry.message.contains(url.lastPathComponent))
      #expect(
        try await Container.shared.silenceStore().content(for: url.lastPathComponent)?.map != nil
      )
    }
  }

  @Test("decode failures are bounded and do not repeatedly retry one file")
  func boundedFailures() async throws {
    let episode = try await Create.podcastEpisode()
    let url = try await cache(episode, playable: false)
    Container.shared.userSettings().$silenceMode.new(.balanced)
    let scheduler = Container.shared.bgTaskScheduler() as! FakeBGTaskScheduler
    Container.shared.silenceProcessor().register()
    try await Wait.until(maxAttempts: 200) {
      scheduler.pendingIdentifiers.contains(identifier)
    } _: {
      "No background work was requested"
    }
    let captured = try await LogCapture.withSink { sink in
      for _ in 0..<3 {
        let task = try #require(scheduler.launchTask(withIdentifier: identifier))
        try await Wait.until(maxAttempts: 200) {
          task.completionCount == 1
        } _: {
          "Failed decoding blocked completion"
        }
        #expect(task.completionResults == [true])
      }
      return sink.captured().filter { $0.message.contains("Silence analysis failed for") }
    }
    #expect(captured.count == 2)
    let content = try #require(
      try await Container.shared.silenceStore().content(for: url.lastPathComponent)
    )
    #expect(content.failureCount == 2)
    #expect(try content.map == nil)
  }

  @Test("an expired background grant never publishes analysis")
  func expiration() async throws {
    let episode = try await Create.podcastEpisode()
    let url = try await cache(episode, playable: true)
    defer { try? FileManager.default.removeItem(at: url) }
    Container.shared.userSettings().$silenceMode.new(.balanced)
    let scheduler = Container.shared.bgTaskScheduler() as! FakeBGTaskScheduler
    Container.shared.silenceProcessor().register()
    try await Wait.until(maxAttempts: 200) {
      scheduler.pendingIdentifiers.contains(identifier)
    } _: {
      "No background work was requested"
    }
    let task = try #require(scheduler.launchTask(withIdentifier: identifier))
    task.expire()
    try await Wait.until(maxAttempts: 200) {
      task.completionCount == 1
    } _: {
      "Expired analysis did not stop"
    }
    #expect(task.completionResults == [false])
    #expect(
      try await Container.shared.silenceStore().content(for: url.lastPathComponent)?.map == nil
    )
  }
}
