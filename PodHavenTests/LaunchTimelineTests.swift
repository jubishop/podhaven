// Copyright Justin Bishop, 2026

import FactoryKit
import FactoryTesting
import Foundation
import SwiftUI
import Testing

@testable import PodHaven

@Suite("of LaunchTimeline tests", .container)
struct LaunchTimelineTests {
  private struct WireMilestone: Decodable, Equatable {
    let milestone: String
    let timestamp: String
    let secondsAfterProcessStart: Double?
  }

  private struct WireLaunch: Decodable {
    let attribution: String
    let pid: Int32
    let sessionID: String?
    let appVersion: String?
    let appBuild: String?
    let gitCommitHash: String?
    let processStart: String?
    let retainedLaunches: Int?
    let unreadableLaunches: Int?
    let lastMilestone: String?
    let milestones: [WireMilestone]?
  }

  private static let processStart = Date(timeIntervalSince1970: 1_790_000_000)

  // A fresh timeline stands in for the next launch of the process.
  private func launch(pid: Int32, startingAfter seconds: TimeInterval) -> LaunchTimeline {
    let start = Self.processStart.addingTimeInterval(seconds)
    Container.shared.launchProcess.register { LaunchProcess(pid: pid, start: start) }
    Container.shared.launchTimeline.reset(.scope)
    return Container.shared.launchTimeline()
  }

  private func at(_ seconds: TimeInterval) {
    Container.shared.fakeDate().freeze(at: Self.processStart.addingTimeInterval(seconds))
  }

  private func decode(_ context: [String: Any]) throws -> WireLaunch {
    try JSONDecoder().decode(WireLaunch.self, from: JSONSerialization.data(withJSONObject: context))
  }

  private static func timestamp(_ seconds: TimeInterval) -> String {
    processStart.addingTimeInterval(seconds)
      .ISO8601Format(.init(includingFractionalSeconds: true))
  }

  @Test("an earlier launch's first milestones reach a later launch's crash context")
  func earlierLaunchIsMatched() throws {
    let killed = launch(pid: 4101, startingAfter: 0)
    at(1.5)
    killed.record(.loggingStarted)
    at(7.25)
    killed.record(.sentryStarted)
    at(9)
    killed.record(.sentryStarted)
    killed.record(.databaseOpened)

    let next = launch(pid: 4202, startingAfter: 3_600)
    let context = try decode(next.crashContext(pid: 4101, endingBy: Self.processStart + 11))

    #expect(context.attribution == "pid_match")
    #expect(context.pid == 4101)
    #expect(context.sessionID == FileLogHandler.sessionID)
    #expect(context.appVersion == AppInfo.version)
    #expect(context.appBuild == AppInfo.buildNumber)
    #expect(context.gitCommitHash == AppInfo.gitCommitHash)
    #expect(context.processStart == Self.timestamp(0))
    #expect(context.retainedLaunches == 1)
    #expect(context.unreadableLaunches == 0)
    #expect(context.lastMilestone == "databaseOpened")
    #expect(
      context.milestones == [
        WireMilestone(
          milestone: "loggingStarted",
          timestamp: Self.timestamp(1.5),
          secondsAfterProcessStart: 1.5
        ),
        WireMilestone(
          milestone: "sentryStarted",
          timestamp: Self.timestamp(7.25),
          secondsAfterProcessStart: 7.25
        ),
        WireMilestone(
          milestone: "databaseOpened",
          timestamp: Self.timestamp(9),
          secondsAfterProcessStart: 9
        ),
      ]
    )
  }

  @Test("a crash matches the latest launch with its pid that started by the crash")
  func reusedPIDMatchesLatestEarlierLaunch() throws {
    at(1)
    launch(pid: 77, startingAfter: 0).record(.loggingStarted)
    at(101)
    launch(pid: 77, startingAfter: 100).record(.databaseOpened)
    at(301)
    launch(pid: 77, startingAfter: 300).record(.bootstrapReturned)

    let current = launch(pid: 88, startingAfter: 400)
    let context = try decode(current.crashContext(pid: 77, endingBy: Self.processStart + 150))

    #expect(context.attribution == "pid_match")
    #expect(context.processStart == Self.timestamp(100))
    #expect(context.lastMilestone == "databaseOpened")
    #expect(context.retainedLaunches == 3)
  }

  @Test("a crash without a retained launch, or naming this launch, reports no match")
  func unretainedLaunchIsNotMatched() throws {
    at(1)
    launch(pid: 10, startingAfter: 0).record(.loggingStarted)

    let current = launch(pid: 11, startingAfter: 60)
    current.record(.loggingStarted)

    for pid: Int32 in [12, 11] {
      let context = try decode(current.crashContext(pid: pid, endingBy: Self.processStart + 120))
      #expect(context.attribution == "not_retained")
      #expect(context.pid == pid)
      #expect(context.retainedLaunches == 1)
      #expect(context.milestones == nil)
    }
  }

  @Test("retention keeps only the newest launches")
  func retentionIsBounded() throws {
    let launches = LaunchTimeline.capacity + 3
    for index in 0..<launches {
      at(Double(index) + 0.5)
      launch(pid: Int32(100 + index), startingAfter: Double(index)).record(.loggingStarted)
    }

    let current = launch(pid: 99, startingAfter: Double(launches))
    let end = Self.processStart.addingTimeInterval(Double(launches))
    let newest = try decode(current.crashContext(pid: Int32(100 + launches - 1), endingBy: end))
    let oldest = try decode(current.crashContext(pid: 100, endingBy: end))

    #expect(newest.attribution == "pid_match")
    #expect(newest.retainedLaunches == LaunchTimeline.capacity - 1)
    #expect(oldest.attribution == "not_retained")
  }

  @Test("the launch Siri catalog publication marks its start and finish")
  func siriPublicationIsMarked() async throws {
    _ = launch(pid: 501, startingAfter: 0)
    let db = Container.shared.appDB()
    db.startSiriCatalog(Container.shared.siriCatalogFile())
    try await db.siriCatalogPublished()

    let next = launch(pid: 502, startingAfter: 60)
    let context = try decode(next.crashContext(pid: 501, endingBy: Self.processStart + 30))

    #expect(
      context.milestones?.map(\.milestone) == [
        "siriCatalogPublicationStarted", "siriCatalogPublicationFinished",
      ]
    )
  }

  @Test("the phone scene marks its first phase and the end of handling it")
  @MainActor func firstScenePhaseIsMarked() async throws {
    _ = launch(pid: 601, startingAfter: 0)
    let sharedState = Container.shared.sharedState()
    let host = TestHostingController(
      rootView: PhoneSceneView(appDelegate: AppDelegate()).environment(\.scenePhase, .inactive)
    )
    try await withHostedTestWindow(host) { _ in
      try await Wait.until(
        { sharedState.scenePhase == .inactive },
        { "Phone scene did not publish its first phase" }
      )
    }

    let next = launch(pid: 602, startingAfter: 60)
    let context = try decode(next.crashContext(pid: 601, endingBy: Self.processStart + 30))

    #expect(context.milestones?.map(\.milestone) == ["firstScenePhase", "firstScenePhaseHandled"])
  }
}
