// Copyright Justin Bishop, 2025

import FactoryKit
import FactoryTesting
import Foundation
import SwiftUI
import Testing

@testable import PodHaven

@Suite("of Navigation tests", .container)
@MainActor class NavigationTests {
  @DynamicInjected(\.navigation) private var navigation
  @DynamicInjected(\.sheet) private var sheet

  private func presentSheet() {
    sheet { Text("test") }
  }

  // MARK: - Settings Navigation

  @Test("showOPMLImport dismisses sheet, sets tab, and sets settings path")
  func showOPMLImport() {
    presentSheet()
    #expect(sheet.config != nil)

    navigation.showOPMLImport()

    #expect(sheet.config == nil)
    #expect(navigation.currentTab == .settings)
    #expect(navigation.settings.path == [.settingsSection(.opml)])
  }

  @Test("showOPMLImport keeps a single OPML entry when invoked repeatedly")
  func showOPMLImportIsIdempotent() {
    navigation.showOPMLImport()
    navigation.showOPMLImport()
    navigation.showOPMLImport()

    #expect(navigation.settings.path == [.settingsSection(.opml)])
  }

  @Test("showTagsSettings dismisses sheet, sets tab, and sets settings path")
  func showTagsSettings() {
    presentSheet()
    #expect(sheet.config != nil)

    navigation.showTagsSettings()

    #expect(sheet.config == nil)
    #expect(navigation.currentTab == .settings)
    #expect(navigation.settings.path == [.settingsSection(.tags)])
  }

  // MARK: - Search Navigation

  @Test("showSharedUnsavedPodcastSeries dismisses sheet, sets tab, and sets search path")
  func showSharedUnsavedPodcastSeries() throws {
    let series = UnsavedPodcastSeries(unsavedPodcast: try Create.unsavedPodcast())

    presentSheet()

    navigation.showSharedUnsavedPodcastSeries(series)

    #expect(sheet.config == nil)
    #expect(navigation.currentTab == .search)
    #expect(navigation.search.path == [.unsavedPodcastSeries(series)])
  }

  @Test(
    "showSharedEpisode dismisses sheet, sets tab, and sets search path with series and episode"
  )
  func showSharedEpisode() throws {
    let unsavedPodcast = try Create.unsavedPodcast()
    let unsavedEpisode = try Create.unsavedEpisode()
    let series = UnsavedPodcastSeries(
      unsavedPodcast: unsavedPodcast,
      unsavedEpisodes: [unsavedEpisode]
    )

    presentSheet()

    navigation.showSharedEpisode(
      unsavedPodcastSeries: series,
      unsavedEpisode: unsavedEpisode
    )

    #expect(sheet.config == nil)
    #expect(navigation.currentTab == .search)
    #expect(
      navigation.search.path == [
        .unsavedPodcastSeries(series),
        .episode(
          DisplayedEpisode(
            UnsavedPodcastEpisode(
              unsavedPodcast: unsavedPodcast,
              unsavedEpisode: unsavedEpisode
            )
          )
        ),
      ]
    )
  }

  // MARK: - UpNext Navigation

  @Test("showOnDeckEpisodeDetail sets tab to upNext without dismissing sheet")
  func showOnDeckEpisodeDetail() {
    navigation.currentTab = .settings
    presentSheet()

    navigation.showOnDeckEpisodeDetail()

    #expect(navigation.currentTab == .upNext)
    #expect(sheet.config != nil)
  }

  @Test("showUpNext dismisses sheet and sets tab to upNext")
  func showUpNext() {
    navigation.currentTab = .settings
    presentSheet()

    navigation.showUpNext()

    #expect(sheet.config == nil)
    #expect(navigation.currentTab == .upNext)
  }

  // MARK: - Podcast Navigation

  @Test("showPodcastList dismisses sheet, sets tab, and sets podcasts path")
  func showPodcastList() {
    presentSheet()

    navigation.showPodcastList(.subscribed)

    #expect(sheet.config == nil)
    #expect(navigation.currentTab == .podcasts)
    #expect(navigation.podcasts.path == [.podcastsViewType(.subscribed)])
  }

  @Test("showPodcast dismisses sheet, sets tab, and sets podcasts path")
  func showPodcast() async throws {
    let podcastEpisode = try await Create.podcastEpisode()
    let podcast = podcastEpisode.podcast

    presentSheet()

    navigation.showPodcast(podcast)

    #expect(sheet.config == nil)
    #expect(navigation.currentTab == .podcasts)
    #expect(
      navigation.podcasts.path == [
        .podcastsViewType(.unsubscribed), .podcast(DisplayedPodcast(podcast)),
      ]
    )
  }

  @Test("showEpisode dismisses sheet, sets tab, and sets podcasts path")
  func showEpisode() async throws {
    let podcastEpisode = try await Create.podcastEpisode(
      UnsavedPodcastEpisode(
        unsavedPodcast: Create.unsavedPodcast(subscriptionDate: Date()),
        unsavedEpisode: Create.unsavedEpisode()
      )
    )

    presentSheet()

    navigation.showEpisode(podcastEpisode)

    #expect(sheet.config == nil)
    #expect(navigation.currentTab == .podcasts)
    #expect(
      navigation.podcasts.path == [
        .podcastsViewType(.subscribed), .podcast(DisplayedPodcast(podcastEpisode.podcast)),
        .episode(DisplayedEpisode(podcastEpisode)),
      ]
    )
  }

  @Test("showEpisode with startTime includes startTime in destination")
  func showEpisodeWithStartTime() async throws {
    let podcastEpisode = try await Create.podcastEpisode(
      UnsavedPodcastEpisode(
        unsavedPodcast: Create.unsavedPodcast(subscriptionDate: Date()),
        unsavedEpisode: Create.unsavedEpisode()
      )
    )

    navigation.showEpisode(podcastEpisode, startTime: 90)

    guard case .episode(_, let startTime) = navigation.podcasts.path[safe: 2] else {
      Issue.record("Expected navigation to episode")
      return
    }
    #expect(startTime == 90)
  }

  @Test("showEpisode with startTime produces different destination than without")
  func showEpisodeStartTimeChangesDestionation() async throws {
    let podcastEpisode = try await Create.podcastEpisode(
      UnsavedPodcastEpisode(
        unsavedPodcast: Create.unsavedPodcast(subscriptionDate: Date()),
        unsavedEpisode: Create.unsavedEpisode()
      )
    )

    let withoutStartTime = Navigation.Destination.episode(DisplayedEpisode(podcastEpisode))
    let withStartTime = Navigation.Destination.episode(
      DisplayedEpisode(podcastEpisode),
      startTime: 90
    )
    #expect(withoutStartTime != withStartTime)
  }

  // MARK: - Same-Tab Sheet Dismissal

  @Test("showOPMLImport dismisses sheet even when already on settings tab")
  func showOPMLImportSameTab() {
    navigation.currentTab = .settings
    presentSheet()

    navigation.showOPMLImport()

    #expect(sheet.config == nil)
  }

  @Test("showTagsSettings dismisses sheet even when already on settings tab")
  func showTagsSettingsSameTab() {
    navigation.currentTab = .settings
    presentSheet()

    navigation.showTagsSettings()

    #expect(sheet.config == nil)
  }

  @Test("showSharedUnsavedPodcastSeries dismisses sheet even when already on search tab")
  func showSharedUnsavedPodcastSeriesSameTab() throws {
    let series = UnsavedPodcastSeries(unsavedPodcast: try Create.unsavedPodcast())
    navigation.currentTab = .search
    presentSheet()

    navigation.showSharedUnsavedPodcastSeries(series)

    #expect(sheet.config == nil)
  }

  @Test("showSharedEpisode dismisses sheet even when already on search tab")
  func showSharedEpisodeSameTab() throws {
    let unsavedPodcast = try Create.unsavedPodcast()
    let unsavedEpisode = try Create.unsavedEpisode()
    let series = UnsavedPodcastSeries(
      unsavedPodcast: unsavedPodcast,
      unsavedEpisodes: [unsavedEpisode]
    )
    navigation.currentTab = .search
    presentSheet()

    navigation.showSharedEpisode(
      unsavedPodcastSeries: series,
      unsavedEpisode: unsavedEpisode
    )

    #expect(sheet.config == nil)
  }

  @Test("showUpNext dismisses sheet even when already on upNext tab")
  func showUpNextSameTab() {
    navigation.currentTab = .upNext
    presentSheet()

    navigation.showUpNext()

    #expect(sheet.config == nil)
  }

  @Test("showPodcastList dismisses sheet even when already on podcasts tab")
  func showPodcastListSameTab() {
    navigation.currentTab = .podcasts
    presentSheet()

    navigation.showPodcastList(.subscribed)

    #expect(sheet.config == nil)
  }

  @Test("showPodcast dismisses sheet even when already on podcasts tab")
  func showPodcastSameTab() async throws {
    let podcast = try await Create.podcastEpisode().podcast
    navigation.currentTab = .podcasts
    presentSheet()

    navigation.showPodcast(podcast)

    #expect(sheet.config == nil)
  }

  @Test("showEpisode dismisses sheet even when already on podcasts tab")
  func showEpisodeSameTab() async throws {
    let podcastEpisode = try await Create.podcastEpisode()
    navigation.currentTab = .podcasts
    presentSheet()

    navigation.showEpisode(podcastEpisode)

    #expect(sheet.config == nil)
  }

  // MARK: - Dismiss

  @Test("dismiss dismisses an active sheet without mutating the current path")
  func dismissSheet() throws {
    let series = UnsavedPodcastSeries(unsavedPodcast: try Create.unsavedPodcast())
    navigation.currentTab = .search
    navigation.search.path = [.unsavedPodcastSeries(series)]
    presentSheet()

    navigation.dismiss()

    #expect(sheet.config == nil)
    #expect(navigation.search.path == [.unsavedPodcastSeries(series)])
  }

  @Test("dismiss pops the last search destination")
  func dismissSearchDestination() throws {
    let series = UnsavedPodcastSeries(unsavedPodcast: try Create.unsavedPodcast())
    let detailPodcast = try Create.unsavedPodcast(title: "Search Detail")
    navigation.currentTab = .search
    navigation.search.path = [
      .unsavedPodcastSeries(series), .podcast(DisplayedPodcast(detailPodcast)),
    ]

    navigation.dismiss()

    #expect(navigation.search.path == [.unsavedPodcastSeries(series)])
  }

  @Test("dismiss pops episode detail but preserves the smart list destination")
  func dismissEpisodeDestination() async throws {
    let smartList = try #require(try await Container.shared.smartListRepo().fetchAll().first)
    let listedEpisode = ListedEpisode(
      UnsavedPodcastEpisode(
        unsavedPodcast: try Create.unsavedPodcast(title: "Episode Root"),
        unsavedEpisode: try Create.unsavedEpisode(title: "Episode Detail")
      )
    )
    navigation.currentTab = .episodes
    navigation.episodes.path = [
      .smartList(smartList.id), .listedEpisode(listedEpisode),
    ]

    navigation.dismiss()

    #expect(navigation.episodes.path == [.smartList(smartList.id)])
  }

  @Test("dismiss keeps the smart list root destination intact")
  func dismissEpisodeSmartListRootNoOp() async throws {
    let smartList = try #require(try await Container.shared.smartListRepo().fetchAll().first)
    navigation.currentTab = .episodes
    navigation.episodes.path = [.smartList(smartList.id)]

    navigation.dismiss()

    #expect(navigation.episodes.path == [.smartList(smartList.id)])
  }

  @Test("dismiss on the episodes hub is a no-op")
  func dismissEpisodeHubNoOp() {
    navigation.currentTab = .episodes
    navigation.episodes.path = []

    navigation.dismiss()

    #expect(navigation.episodes.path.isEmpty)
  }

}
