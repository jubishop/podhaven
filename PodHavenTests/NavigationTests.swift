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

  @Test("showOPMLImport dismisses sheet, sets tab, and appends to settings path")
  func showOPMLImport() {
    presentSheet()
    #expect(sheet.config != nil)

    navigation.showOPMLImport()

    #expect(sheet.config == nil)
    #expect(navigation.currentTab == .settings)
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

  // MARK: - SavedPathManager

  @Test("podcasts tab saves top destination when path changes")
  func podcastsTabSavesTopDestination() {
    navigation.showPodcastList(.subscribed)
    #expect(navigation.podcasts.path == [.podcastsViewType(.subscribed)])

    navigation.showPodcastList(.unsubscribed)
    #expect(navigation.podcasts.path == [.podcastsViewType(.unsubscribed)])
  }

  @Test("clearing podcasts path resets top destination")
  func clearingPodcastsPathResetsTopDestination() {
    navigation.showPodcastList(.subscribed)
    #expect(navigation.podcasts.path.count == 1)

    navigation.podcasts.path = []
    #expect(navigation.podcasts.path.isEmpty)
  }
}
