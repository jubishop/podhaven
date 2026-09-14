// Copyright Justin Bishop, 2026

import FactoryKit
import Foundation
import SwiftUI
import Tagged
import Testing

@testable import PodHaven

private final class SilenceAudioBundle: NSObject {}

@Suite("Silence audio decoding", .container)
struct SilenceAudioTests {
  @Test("registration waits for a foreground signal or an OS background grant")
  func backgroundRegistration() async throws {
    let episode = try await Create.podcastEpisode()
    let task = try await CacheHelpers.downloadToCache(episode.id)
    try await CacheHelpers.simulateBackgroundFinish(task)
    let url = try await CacheHelpers.waitForCached(episode.id)
    Container.shared.userSettings().$silenceMode.new(.balanced)
    let scheduler = Container.shared.bgTaskScheduler() as! FakeBGTaskScheduler
    Container.shared.silenceProcessor().register()
    try await Wait.until(maxAttempts: 200) {
      scheduler.pendingIdentifiers.contains("\(AppInfo.bundleIdentifier).silenceAnalysis")
    } _: {
      "Background-only registration did not request an OS work grant"
    }
    #expect(
      try await Container.shared.silenceStore().content(for: url.lastPathComponent)?.map == nil
    )
  }

  @Test(
    "real MP3 and AAC decoders preserve tones and opposite-phase stereo",
    arguments: ["mp3", "m4a"]
  )
  func decode(_ fileExtension: String) async throws {
    let name = fileExtension == "mp3" ? "silence-mono-vbr" : "silence-stereo"
    let url = try #require(
      Bundle(for: SilenceAudioBundle.self).url(forResource: name, withExtension: fileExtension)
    )
    let map = try await SilenceAnalyzer.analyze(url, progress: { _, _ in })
    #expect(map.isValid)
    #expect(map.intervals.count == 8)
    for (index, interval) in map.intervals.enumerated() {
      #expect(abs(interval.start - (Double(index) * 4 + 2)) < 0.1)
      #expect(abs(interval.end - (Double(index) * 4 + 4)) < 0.1)
    }
  }

  @Test("decode failures never publish an empty successful map")
  func invalidFile() async throws {
    let url = URL.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".mp3")
    try Data("not audio".utf8).write(to: url)
    defer { try? FileManager.default.removeItem(at: url) }
    await #expect(throws: (any Error).self) {
      try await SilenceAnalyzer.analyze(url, progress: { _, _ in })
    }
  }

  @Test("an eligible download outside the queue is analyzed after thermal recovery")
  func nonQueuedDownload() async throws {
    let episode = try await Create.podcastEpisode()
    let task = try await CacheHelpers.downloadToCache(episode.id)
    try await CacheHelpers.simulateBackgroundFinish(task)
    let url = try await CacheHelpers.waitForCached(episode.id)
    let fixture = try #require(
      Bundle(for: SilenceAudioBundle.self)
        .url(forResource: "silence-mono-vbr", withExtension: "mp3")
    )
    try FileManager.default.createDirectory(
      at: url.rawValue.deletingLastPathComponent(),
      withIntermediateDirectories: true
    )
    try FileManager.default.copyItem(at: fixture, to: url.rawValue)
    defer { try? FileManager.default.removeItem(at: url.rawValue) }
    let state = Container.shared.sharedState()
    state.setThermalPressure(.serious)
    Container.shared.userSettings().$silenceMode.new(.balanced)
    Container.shared.silenceProcessor().register()
    Container.shared.silenceProcessor().handleScenePhaseChange(to: .active)
    let store = Container.shared.silenceStore()
    #expect(try await Container.shared.repo().episode(episode.id)?.queueOrder == nil)
    #expect(try await store.content(for: url.lastPathComponent)?.map == nil)
    state.setThermalPressure(.nominal)
    let prepared: SilenceMap = try await Wait.forValue {
      try await store.content(for: url.lastPathComponent)?.map
    }
    #expect(prepared.intervals.count == 8)
    Container.shared.userSettings().$silenceMode.new(.off)
    #expect(try await store.content(for: url.lastPathComponent)?.map == prepared)
    Container.shared.silenceProcessor().handleScenePhaseChange(to: .background)
  }
}
