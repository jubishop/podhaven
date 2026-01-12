// Copyright Justin Bishop, 2025

import FactoryKit
import FactoryTesting
import Foundation
import SwiftUI
import Testing
import UserNotifications

@testable import PodHaven

@Suite("of UserNotificationManager tests", .container)
actor UserNotificationManagerTests {
  @DynamicInjected(\.userNotificationCenter) private var userNotificationCenter
  @DynamicInjected(\.userNotificationManager) private var userNotificationManager
  @DynamicInjected(\.repo) private var repo

  var fakeCenter: FakeUserNotificationCenter {
    userNotificationCenter as! FakeUserNotificationCenter
  }

  // MARK: - Initialize

  @Test("initialize refreshes authorization status from center")
  func initializeRefreshesAuthorizationStatus() async {
    fakeCenter.setAuthorizationStatus(.denied)

    await userNotificationManager.initialize()

    #expect(userNotificationManager.authorizationStatus == .denied)
  }

  // MARK: - Refresh Authorization Status

  @Test("refreshAuthorizationStatus updates status from center")
  func refreshAuthorizationStatusUpdatesFromCenter() async {
    fakeCenter.setAuthorizationStatus(.authorized)

    await userNotificationManager.refreshAuthorizationStatus()

    #expect(userNotificationManager.authorizationStatus == .authorized)
  }

  // MARK: - Handle Scene Phase Change

  @Test("handleScenePhaseChange refreshes status when active")
  func handleScenePhaseChangeRefreshesWhenActive() async {
    fakeCenter.setAuthorizationStatus(.provisional)

    await userNotificationManager.handleScenePhaseChange(to: .active)

    #expect(userNotificationManager.authorizationStatus == .provisional)
  }

  @Test("handleScenePhaseChange does nothing when inactive")
  func handleScenePhaseChangeDoesNothingWhenInactive() async {
    fakeCenter.setAuthorizationStatus(.denied)
    await userNotificationManager.refreshAuthorizationStatus()
    #expect(userNotificationManager.authorizationStatus == .denied)

    fakeCenter.setAuthorizationStatus(.authorized)
    await userNotificationManager.handleScenePhaseChange(to: .inactive)

    #expect(userNotificationManager.authorizationStatus == .denied)
  }

  @Test("handleScenePhaseChange does nothing when background")
  func handleScenePhaseChangeDoesNothingWhenBackground() async {
    fakeCenter.setAuthorizationStatus(.denied)
    await userNotificationManager.refreshAuthorizationStatus()

    fakeCenter.setAuthorizationStatus(.authorized)
    await userNotificationManager.handleScenePhaseChange(to: .background)

    #expect(userNotificationManager.authorizationStatus == .denied)
  }

  // MARK: - Computed Properties

  @Test("isAuthorized returns true for authorized status")
  func isAuthorizedReturnsTrueForAuthorized() async {
    fakeCenter.setAuthorizationStatus(.authorized)
    await userNotificationManager.refreshAuthorizationStatus()

    #expect(userNotificationManager.isAuthorized == true)
  }

  @Test("isAuthorized returns true for provisional status")
  func isAuthorizedReturnsTrueForProvisional() async {
    fakeCenter.setAuthorizationStatus(.provisional)
    await userNotificationManager.refreshAuthorizationStatus()

    #expect(userNotificationManager.isAuthorized == true)
  }

  @Test("isAuthorized returns true for ephemeral status")
  func isAuthorizedReturnsTrueForEphemeral() async {
    fakeCenter.setAuthorizationStatus(.ephemeral)
    await userNotificationManager.refreshAuthorizationStatus()

    #expect(userNotificationManager.isAuthorized == true)
  }

  @Test("isAuthorized returns false for denied status")
  func isAuthorizedReturnsFalseForDenied() async {
    fakeCenter.setAuthorizationStatus(.denied)
    await userNotificationManager.refreshAuthorizationStatus()

    #expect(userNotificationManager.isAuthorized == false)
  }

  @Test("isAuthorized returns false for notDetermined status")
  func isAuthorizedReturnsFalseForNotDetermined() async {
    fakeCenter.setAuthorizationStatus(.notDetermined)
    await userNotificationManager.refreshAuthorizationStatus()

    #expect(userNotificationManager.isAuthorized == false)
  }

  @Test("isDenied returns true only for denied status")
  func isDeniedReturnsTrueOnlyForDenied() async {
    fakeCenter.setAuthorizationStatus(.denied)
    await userNotificationManager.refreshAuthorizationStatus()

    #expect(userNotificationManager.isDenied == true)

    fakeCenter.setAuthorizationStatus(.authorized)
    await userNotificationManager.refreshAuthorizationStatus()

    #expect(userNotificationManager.isDenied == false)
  }

  @Test("isNotDetermined returns true only for notDetermined status")
  func isNotDeterminedReturnsTrueOnlyForNotDetermined() async {
    fakeCenter.setAuthorizationStatus(.notDetermined)
    await userNotificationManager.refreshAuthorizationStatus()

    #expect(userNotificationManager.isNotDetermined == true)

    fakeCenter.setAuthorizationStatus(.authorized)
    await userNotificationManager.refreshAuthorizationStatus()

    #expect(userNotificationManager.isNotDetermined == false)
  }

  // MARK: - Request Authorization If Needed

  @Test("requestAuthorizationIfNeeded returns true when already authorized")
  func requestAuthorizationIfNeededReturnsTrueWhenAuthorized() async {
    fakeCenter.setAuthorizationStatus(.authorized)

    let result = await userNotificationManager.requestAuthorizationIfNeeded()

    #expect(result == true)
    #expect(fakeCenter.requestAuthorizationCalls.isEmpty)
  }

  @Test("requestAuthorizationIfNeeded returns true when provisional")
  func requestAuthorizationIfNeededReturnsTrueWhenProvisional() async {
    fakeCenter.setAuthorizationStatus(.provisional)

    let result = await userNotificationManager.requestAuthorizationIfNeeded()

    #expect(result == true)
    #expect(fakeCenter.requestAuthorizationCalls.isEmpty)
  }

  @Test("requestAuthorizationIfNeeded returns false when denied")
  func requestAuthorizationIfNeededReturnsFalseWhenDenied() async {
    fakeCenter.setAuthorizationStatus(.denied)

    let result = await userNotificationManager.requestAuthorizationIfNeeded()

    #expect(result == false)
    #expect(fakeCenter.requestAuthorizationCalls.isEmpty)
  }

  @Test("requestAuthorizationIfNeeded requests authorization when not determined")
  func requestAuthorizationIfNeededRequestsWhenNotDetermined() async {
    fakeCenter.setAuthorizationStatus(.notDetermined)
    fakeCenter.setRequestAuthorizationResult(true)

    let result = await userNotificationManager.requestAuthorizationIfNeeded()

    #expect(result == true)
    #expect(fakeCenter.requestAuthorizationCalls.count == 1)
    #expect(fakeCenter.requestAuthorizationCalls.first == [.alert, .sound, .badge])
  }

  @Test("requestAuthorizationIfNeeded returns false when authorization denied by user")
  func requestAuthorizationIfNeededReturnsFalseWhenUserDenies() async {
    fakeCenter.setAuthorizationStatus(.notDetermined)
    fakeCenter.setRequestAuthorizationResult(false)

    let result = await userNotificationManager.requestAuthorizationIfNeeded()

    #expect(result == false)
    #expect(fakeCenter.requestAuthorizationCalls.count == 1)
  }

  @Test("requestAuthorizationIfNeeded returns false when authorization throws error")
  func requestAuthorizationIfNeededReturnsFalseOnError() async {
    fakeCenter.setAuthorizationStatus(.notDetermined)
    fakeCenter.setRequestAuthorizationError(TestError.notificationAuthorizationFailed)

    let result = await userNotificationManager.requestAuthorizationIfNeeded()

    #expect(result == false)
    #expect(fakeCenter.requestAuthorizationCalls.count == 1)
  }

  // MARK: - Schedule New Episode Notification

  @Test("scheduleNewEpisodeNotification does nothing with empty episodes")
  func scheduleNewEpisodeNotificationSkipsEmptyEpisodes() async throws {
    let podcast = try await Create.podcast()
    fakeCenter.setAuthorizationStatus(.authorized)

    await userNotificationManager.scheduleNewEpisodeNotification(
      podcast: podcast,
      episodes: []
    )

    #expect(fakeCenter.addedRequests.isEmpty)
  }

  @Test("scheduleNewEpisodeNotification does nothing when not authorized")
  func scheduleNewEpisodeNotificationSkipsWhenNotAuthorized() async throws {
    let podcastEpisode = try await Create.podcastEpisode()
    fakeCenter.setAuthorizationStatus(.denied)

    await userNotificationManager.scheduleNewEpisodeNotification(
      podcast: podcastEpisode.podcast,
      episodes: [podcastEpisode.episode]
    )

    #expect(fakeCenter.addedRequests.isEmpty)
  }

  @Test("scheduleNewEpisodeNotification uses episode title for single episode")
  func scheduleNewEpisodeNotificationUsesSingleEpisodeTitle() async throws {
    let podcastEpisode = try await Create.podcastEpisode()
    fakeCenter.setAuthorizationStatus(.authorized)

    await userNotificationManager.scheduleNewEpisodeNotification(
      podcast: podcastEpisode.podcast,
      episodes: [podcastEpisode.episode]
    )

    #expect(fakeCenter.addedRequests.count == 1)
    let request = fakeCenter.addedRequests.first!
    #expect(request.title == podcastEpisode.podcast.title)
    #expect(request.body == podcastEpisode.episode.title)
    #expect(request.hasSound == true)
  }

  @Test("scheduleNewEpisodeNotification uses episode count for multiple episodes")
  func scheduleNewEpisodeNotificationUsesCountForMultipleEpisodes() async throws {
    let repo = Container.shared.repo()
    let podcastSeries = try await repo.insertSeries(
      UnsavedPodcastSeries(
        unsavedPodcast: try Create.unsavedPodcast(),
        unsavedEpisodes: [
          try Create.unsavedEpisode(),
          try Create.unsavedEpisode(),
          try Create.unsavedEpisode(),
        ]
      )
    )
    fakeCenter.setAuthorizationStatus(.authorized)

    await userNotificationManager.scheduleNewEpisodeNotification(
      podcast: podcastSeries.podcast,
      episodes: Array(podcastSeries.episodes)
    )

    #expect(fakeCenter.addedRequests.count == 1)
    let request = fakeCenter.addedRequests.first!
    #expect(request.title == podcastSeries.podcast.title)
    #expect(request.body == "3 new episodes available")
    #expect(request.hasSound == true)
  }
}
