// Copyright Justin Bishop, 2026

import FactoryKit
import FactoryTesting
import Foundation
import Semaphore
import SwiftUI
import Testing

@testable import PodHaven

// Timing suite: bin/test-all runs it in its own test host so other tests'
// main-thread work cannot count against its budgets.
@Suite("of large OPML imports", .container)
@MainActor struct OPMLLargeImportTests {
  @DynamicInjected(\.opmlViewModel) private var opmlViewModel
  @DynamicInjected(\.podcastFeedSession) private var podcastFeedSession
  @DynamicInjected(\.podcastOPMLSession) private var podcastOPMLSession
  @DynamicInjected(\.repo) private var repo

  private static let feedCount = 5_000
  private static let episodesPerFeed = 20
  // Apple counts main-thread work this long as a hang.
  private static let hangThreshold: Duration = .milliseconds(250)
  private static let opmlURL = URL(string: "file:///large.opml")!

  // One sequential flow, so no other import shares the main thread being measured.
  @Test("a stopped 5,000-feed import and its reimport stay responsive and finish within budget")
  func stopAndReimport() async throws {
    let finishedBeforeStop = 100
    let gated = ThreadSafe(true)
    let release = AsyncSemaphore(value: 0)
    try await respondToFeeds { request in
      if gated(), request > finishedBeforeStop { try await release.waitUnlessCancelled() }
    }

    let host = TestHostingController(rootView: ImportSheetHost(viewModel: opmlViewModel))
    try await withHostedTestWindow(host) { _ in
      let stopping = MainThreadMonitor()
      stopping.start()
      let importTask = Task { await opmlViewModel.importOPMLFromURL(url: Self.opmlURL) }
      let stoppedFile = try await Wait.forValue { await opmlViewModel.opmlFile }
      try await Wait.until(
        { @MainActor in stoppedFile.finished.count == finishedBeforeStop },
        { @MainActor in
          "Expected \(finishedBeforeStop) finished, got \(stoppedFile.finished.count)"
        }
      )
      let stopStarted = ContinuousClock.now
      opmlViewModel.stopDownloading()
      await importTask.value
      try await Wait.until(
        { @MainActor in opmlViewModel.opmlFile == nil },
        { "Stopping the import did not dismiss its sheet" }
      )
      let stopDuration = ContinuousClock.now - stopStarted
      host.view.layoutIfNeeded()
      stopping.stop()

      #expect(try await repo.allPodcasts(AppDB.noOp).count == finishedBeforeStop)
      print("OPML stopped import durationMs=\(stopDuration.milliseconds) \(stopping.summary)")
      #expect(stopDuration < .seconds(5), "Stopping the import exceeded its duration budget")
      #expect(
        stopping.longestBusy < Self.hangThreshold,
        "Main thread stayed busy for \(stopping.longestBusy.milliseconds) ms while stopping"
      )

      gated(false)
      let importing = MainThreadMonitor()
      importing.start()
      let importStarted = ContinuousClock.now
      await opmlViewModel.importOPMLFromURL(url: Self.opmlURL)
      let importDuration = ContinuousClock.now - importStarted
      host.view.layoutIfNeeded()
      importing.stop()

      let opmlFile = try #require(opmlViewModel.opmlFile)
      #expect(opmlFile.finished.count == Self.feedCount)
      #expect(opmlFile.failed.isEmpty)
      #expect(opmlFile.inProgressCount == 0)
      let podcasts = try await repo.allPodcasts(AppDB.noOp)
      #expect(podcasts.count == Self.feedCount)
      #expect(podcasts.allSatisfy { $0.subscribed })
      print("OPML large import durationMs=\(importDuration.milliseconds) \(importing.summary)")
      #expect(importDuration < .seconds(60), "Synthetic import exceeded its duration budget")
      #expect(
        importing.longestBusy < Self.hangThreshold,
        "Main thread stayed busy for \(importing.longestBusy.milliseconds) ms during the import"
      )
    }
  }

  // MARK: - Helpers

  // `delay` receives each feed request's 1-based arrival order.
  private func respondToFeeds(
    after delay: @escaping @Sendable (Int) async throws -> Void
  ) async throws {
    let opmlSession = try #require(podcastOPMLSession as? FakeDataFetchable)
    let feedSession = try #require(podcastFeedSession as? FakeDataFetchable)
    await opmlSession.respond(
      to: Self.opmlURL,
      data: SyntheticFeed.opml(feedCount: Self.feedCount)
    )
    let requests = ThreadSafe(0)
    await SyntheticFeed.respond(feedSession, episodes: Self.episodesPerFeed) { _ in
      try await delay(
        requests { count in
          count += 1
          return count
        }
      )
    }
  }
}

private struct ImportSheetHost: View {
  let viewModel: OPMLViewModel

  var body: some View {
    if let opmlFile = viewModel.opmlFile {
      VStack {
        OPMLImportSheet(viewModel: viewModel, opmlFile: opmlFile)
      }
    }
  }
}

// Measures the main thread's own CPU time between run-loop timer ticks, so a
// long block means main-thread work rather than a busy machine delaying it.
@MainActor private final class MainThreadMonitor {
  private var timer: Timer?
  private var lastWall: ContinuousClock.Instant?
  private var lastCPU: UInt64 = 0
  private var wallGaps: [Duration] = []
  private var busyBlocks: [Duration] = []

  var longestBusy: Duration { busyBlocks.max() ?? .zero }

  var summary: String {
    """
    ticks=\(busyBlocks.count) \
    longestBusyMs=\(longestBusy.milliseconds) \
    busyOver100Ms=\(busyBlocks.count { $0 > .milliseconds(100) }) \
    totalBusyMs=\(busyBlocks.reduce(.zero, +).milliseconds) \
    longestWallGapMs=\((wallGaps.max() ?? .zero).milliseconds)
    """
  }

  func start() {
    lastWall = .now
    lastCPU = clock_gettime_nsec_np(CLOCK_THREAD_CPUTIME_ID)
    let timer = Timer(timeInterval: 0.01, repeats: true) { [weak self] _ in
      MainActor.assumeIsolated { self?.tick() }
    }
    RunLoop.main.add(timer, forMode: .common)
    self.timer = timer
  }

  func stop() {
    tick()
    timer?.invalidate()
    timer = nil
  }

  private func tick() {
    let wall = ContinuousClock.now
    let cpu = clock_gettime_nsec_np(CLOCK_THREAD_CPUTIME_ID)
    if let lastWall {
      wallGaps.append(wall - lastWall)
      busyBlocks.append(.nanoseconds(cpu - lastCPU))
    }
    lastWall = wall
    lastCPU = cpu
  }
}

extension Duration {
  fileprivate var milliseconds: Int64 {
    components.seconds * 1_000 + components.attoseconds / 1_000_000_000_000_000
  }
}
