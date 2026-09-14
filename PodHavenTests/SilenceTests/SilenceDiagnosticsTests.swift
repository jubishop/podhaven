// Copyright Justin Bishop, 2026

import FactoryKit
import Foundation
import Logging
import Testing

@testable import PodHaven

private final class SilenceDiagnosticsBundle: NSObject {}

@Suite("Silence analysis diagnostics", .container)
struct SilenceDiagnosticsTests {
  private let identifier = "\(AppInfo.bundleIdentifier).silenceAnalysis"

  private func prepare() async throws -> URL {
    let episode = try await Create.podcastEpisode()
    let download = try await CacheHelpers.downloadToCache(episode.id)
    try await CacheHelpers.simulateBackgroundFinish(download)
    let url = try await CacheHelpers.waitForCached(episode.id).rawValue
    let fixture = try #require(
      Bundle(for: SilenceDiagnosticsBundle.self)
        .url(forResource: "silence-mono-vbr", withExtension: "mp3")
    )
    try FileManager.default.createDirectory(
      at: url.deletingLastPathComponent(),
      withIntermediateDirectories: true
    )
    try FileManager.default.copyItem(at: fixture, to: url)
    Container.shared.userSettings().$silenceMode.new(.balanced)
    Container.shared.silenceProcessor().register()
    let scheduler = Container.shared.bgTaskScheduler() as! FakeBGTaskScheduler
    try await Wait.until {
      scheduler.pendingIdentifiers.contains(identifier)
    } _: {
      "Silence work was not scheduled"
    }
    return url
  }

  @Test("fast background scans keep complete correlated summaries below warning")
  func fastCompletion() async throws {
    let url = try await prepare()
    defer { try? FileManager.default.removeItem(at: url) }
    Container.shared.fakeContinuousClock().freeze()
    let scheduler = Container.shared.bgTaskScheduler() as! FakeBGTaskScheduler
    let entries = try await LogCapture.withSink { sink in
      Container.shared.continuousClockNow.reset(.scope)
      let task = try #require(scheduler.launchTask(withIdentifier: identifier))
      try await Wait.until {
        task.completionCount == 1
      } _: {
        "Silence work did not finish"
      }
      #expect(task.completionResults == [true])
      return sink.captured()
    }
    let summary = try #require(entries.first { $0.message.contains("event=silenceRunFinished") })
    #expect(summary.level == .info)
    for field in [
      "mode=background", "outcome=completed", "publishedFiles=1", "completedFiles=1",
      "discardedAudioSeconds=0.0", "runID=", "processCPUSeconds=", "thermal=nominal",
      "transcriptionActive=false", "embeddingActive=false", "taskPriority=", "sessionRuns=1",
    ] {
      #expect(summary.message.contains(field), "Missing field: \(field)")
    }
    #expect(entries.filter { $0.label.contains("Silence") && $0.level >= .warning }.isEmpty)
  }

  @Test("a slow scan warns during decoding and once at completion without buffer spam")
  func slowScan() async throws {
    let url = try await prepare()
    defer { try? FileManager.default.removeItem(at: url) }
    let scheduler = Container.shared.bgTaskScheduler() as! FakeBGTaskScheduler
    let base = ContinuousClock.now
    let entries = try await LogCapture.withSink { sink in
      Container.shared.continuousClockNow.context(.test) {
        {
          if sink.captured().contains(where: { $0.message.contains("event=silenceAttemptStarted") })
          {
            return base.advanced(by: .seconds(20))
          }
          return base
        }
      }
      Container.shared.continuousClockNow.reset(.scope)
      let task = try #require(scheduler.launchTask(withIdentifier: identifier))
      try await Wait.until {
        task.completionCount == 1
      } _: {
        "Silence work did not finish"
      }
      #expect(task.completionResults == [true])
      return sink.captured()
    }
    let warnings = entries.filter { $0.label.contains("Silence") && $0.level == .warning }
    #expect(warnings.count == 2)
    let early = try #require(warnings.first { $0.message.contains("event=silenceRunSlow") })
    #expect(early.message.contains("publishedFiles=0"))
    #expect(early.message.contains("wallSeconds=20.0"))
    #expect(early.message.contains("outcome=running"))
    let earlyIndex = try #require(entries.firstIndex { $0.message == early.message })
    let completionIndex = try #require(
      entries.firstIndex { $0.message.contains("event=silenceAttemptFinished") }
    )
    #expect(earlyIndex < completionIndex)
    #expect(warnings.last?.message.contains("outcome=completed") == true)
  }

  @Test(
    "interruption retains discarded progress without publishing a silence map",
    arguments: ["backgroundExpiration", "thermal", "eligibility"]
  )
  func interruptedScan(_ stopReason: String) async throws {
    let url = try await prepare()
    defer { try? FileManager.default.removeItem(at: url) }
    let scheduler = Container.shared.bgTaskScheduler() as! FakeBGTaskScheduler
    let running = ThreadSafe<FakeBGTask?>(nil)
    let base = ContinuousClock.now
    let entries = try await LogCapture.withSink { sink in
      Container.shared.continuousClockNow.context(.test) {
        {
          if sink.captured().contains(where: { $0.message.contains("event=silenceAttemptStarted") })
          {
            switch stopReason {
            case "thermal": Container.shared.sharedState().setThermalPressure(.serious)
            case "eligibility": Container.shared.userSettings().$silenceMode.new(.off)
            default: running()?.expire()
            }
          }
          return base
        }
      }
      Container.shared.continuousClockNow.reset(.scope)
      let task = try #require(scheduler.launchTask(withIdentifier: identifier))
      running(task)
      try await Wait.until {
        task.completionCount == 1
      } _: {
        "Silence work did not finish"
      }
      if stopReason == "backgroundExpiration" {
        #expect(task.completionResults == [false])
      }
      return sink.captured()
    }
    let summary = try #require(entries.first { $0.message.contains("event=silenceRunFinished") })
    #expect(summary.level == (stopReason == "thermal" ? .warning : .info))
    #expect(summary.message.contains("stopReason=\(stopReason)"))
    #expect(summary.message.contains("publishedFiles=0"))
    #expect(!summary.message.contains("discardedAudioSeconds=0.0"))
    #expect(
      summary.message.contains("expirationCount=\(stopReason == "backgroundExpiration" ? 1 : 0)")
    )
    #expect(
      try await Container.shared.silenceStore().content(for: url.lastPathComponent)?.map == nil
    )
  }
}
