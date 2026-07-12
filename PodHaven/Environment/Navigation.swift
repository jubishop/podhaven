// Copyright Justin Bishop, 2025

import FactoryKit
import GRDB
import IdentifiedCollections
import Logging
import SwiftNavigation
import SwiftUI
import UIKit

extension Container {
  @MainActor var navigation: Factory<Navigation> {
    Factory(self) { Navigation() }.scope(.cached)
  }
}

@Observable @MainActor class Navigation {
  @ObservationIgnored @DynamicInjected(\.sharedState) private var sharedState
  @ObservationIgnored @DynamicInjected(\.sheet) private var sheet
  @ObservationIgnored @DynamicInjected(\.userSettings) private var userSettings

  @MainActor
  protocol ManagingPath: AnyObject, Observable {
    var path: [Destination] { get set }
  }

  @MainActor @Observable
  class PathManager: ManagingPath {
    var path: [Destination] = [] {
      didSet {
        if path.count < oldValue.count {
          Self.log.debug("Path popped: \(oldValue.count) → \(path.count)")
        }
      }
    }

    private static let log = Log.as("Navigation")
  }

  private static let log = Log.as("Navigation")

  // MARK: - Tab Management

  enum Tab {
    case settings, search, upNext, episodes, podcasts
  }

  var currentTab: Tab = .upNext {
    didSet {
      if currentTab == oldValue {
        Self.log.debug("Tab re-selected: \(currentTab)")
      } else {
        Self.log.debug("Tab changed: \(oldValue) → \(currentTab)")
      }
    }
  }

  // MARK: - Unified Navigation Destination

  @CasePathable
  enum Destination: Hashable {
    // Settings destinations
    case settingsSection(SettingsSection)

    // Episodes destinations
    case smartList(SmartList.ID)

    // Podcasts destinations
    case podcastsViewType(PodcastsViewType)

    // Universal destinations
    case podcast(DisplayedPodcast)
    case episode(DisplayedEpisode, startTime: Int?)
    case listedPodcast(ListedPodcast)
    case listedEpisode(ListedEpisode, similarityScore: Float?)
    case unsavedPodcastSeries(UnsavedPodcastSeries)
    case searchDiscovery(SearchDiscoveryListViewModel)

    static func episode(_ episode: DisplayedEpisode) -> Destination {
      .episode(episode, startTime: nil)
    }

    static func listedEpisode(_ listedEpisode: ListedEpisode) -> Destination {
      .listedEpisode(listedEpisode, similarityScore: nil)
    }
  }

  enum SettingsSection {
    case opml
    case tags
    case swipeActions
    case feedback
  }

  enum PodcastsViewType: Hashable, Sendable {
    case subscribed
    case unsubscribed
    case untagged
    case tag(Tag.ID)
    case freshnessCadence(FreshnessCadence)
    case queueOnTop
    case queueOnBottom
    case autoCache
    case autoSave
    case notifyNewEpisodes

    // Fixed icon for the built-in list types. `.tag` uses the tag's own
    // user-chosen icon, supplied by callers, so its value here is a fallback.
    var icon: LucideIcon {
      switch self {
      case .subscribed: .circleCheck
      case .unsubscribed: .circleX
      case .untagged: .inbox
      case .tag: .tag
      case .freshnessCadence(let cadence): cadence.icon
      case .queueOnTop: .arrowUpToLine
      case .queueOnBottom: .arrowDownToLine
      case .autoCache: .download
      case .autoSave: .bookmark
      case .notifyNewEpisodes: .bell
      }
    }
  }

  @ViewBuilder
  func navigationDestination(for destination: Destination) -> some View {
    switch destination {
    // Settings destinations
    case .settingsSection(let section):
      switch section {
      case .opml:
        OPMLView().id("opml")
      case .tags:
        TagsSettingsView().id("tags")
      case .swipeActions:
        EpisodeSwipeSettingsView().id("swipeActions")
      case .feedback:
        FeedbackFormView().id("feedback")
      }

    // Episodes destinations
    case .smartList(let smartListID):
      if let smartList = sharedState.smartLists[id: smartListID] {
        EpisodesListView(viewModel: EpisodesListViewModel(smartList: smartList))
          .id("smartList-\(smartListID)")
      } else {
        deferredHubPop(
          episodes,
          message: "Smart list \(smartListID) missing from sharedState; popping to the hub"
        )
      }

    // Podcasts destinations
    case .podcastsViewType(let viewType):
      switch viewType {
      case .subscribed:
        PodcastsListView(
          viewModel: PodcastsListViewModel(
            title: "Subscribed",
            filter: { $0.filter(Podcast.subscribed) },
            icon: viewType.icon
          )
        )
        .id("subscribed")
      case .unsubscribed:
        PodcastsListView(
          viewModel: PodcastsListViewModel(
            title: "Unsubscribed",
            filter: { $0.filter(Podcast.unsubscribed) },
            icon: viewType.icon
          )
        )
        .id("unsubscribed")
      case .untagged:
        PodcastsListView(
          viewModel: PodcastsListViewModel(
            title: "Untagged",
            filter: { $0.having(Podcast.podcastTags.isEmpty) },
            icon: viewType.icon
          )
        )
        .id("untagged")
      case .tag(let tagID):
        if let tag = sharedState.tags[id: tagID] {
          PodcastsListView(
            viewModel: PodcastsListViewModel(
              title: tag.name,
              filter: Podcast.hasTag(tagID),
              icon: tag.icon
            )
          )
          .id("tag-\(tagID)")
        } else {
          deferredHubPop(
            podcasts,
            message: "Tag \(tagID) missing from sharedState; popping to the hub"
          )
        }
      case .freshnessCadence(let cadence):
        PodcastsListView(
          viewModel: PodcastsListViewModel(
            title: cadence.displayName,
            filter: { $0.filter(Podcast.resolvedFreshnessCadence(cadence)) },
            icon: viewType.icon
          )
        )
        .id("freshness-\(cadence.rawValue)")
      case .queueOnTop:
        PodcastsListView(
          viewModel: PodcastsListViewModel(
            title: "Queue On Top",
            filter: { $0.filter(Podcast.queuesAllEpisodes(.onTop)) },
            icon: viewType.icon
          )
        )
        .id("queueOnTop")
      case .queueOnBottom:
        PodcastsListView(
          viewModel: PodcastsListViewModel(
            title: "Queue On Bottom",
            filter: { $0.filter(Podcast.queuesAllEpisodes(.onBottom)) },
            icon: viewType.icon
          )
        )
        .id("queueOnBottom")
      case .autoCache:
        PodcastsListView(
          viewModel: PodcastsListViewModel(
            title: "Cache",
            filter: { $0.filter(Podcast.cachesAllEpisodes(.cache)) },
            icon: viewType.icon
          )
        )
        .id("autoCache")
      case .autoSave:
        PodcastsListView(
          viewModel: PodcastsListViewModel(
            title: "Save",
            filter: { $0.filter(Podcast.cachesAllEpisodes(.save)) },
            icon: viewType.icon
          )
        )
        .id("autoSave")
      case .notifyNewEpisodes:
        PodcastsListView(
          viewModel: PodcastsListViewModel(
            title: "Notify",
            filter: { $0.filter(Podcast.notifiesNewEpisodes) },
            icon: viewType.icon
          )
        )
        .id("notifyNewEpisodes")
      }

    // Universal destinations
    case .episode(let episode, let startTime):
      // Composite identity: re-opening the same episode with a different startTime
      // must produce a fresh view instance so the auto-play seek triggers anew.
      EpisodeDetailView(viewModel: EpisodeDetailViewModel(episode: episode, startTime: startTime))
        .id("\(episode.id)-\(startTime ?? 0)")
    case .podcast(let podcast):
      PodcastDetailView(viewModel: PodcastDetailViewModel(podcast: podcast))
        .id(podcast.id)
    case .listedPodcast(let listedPodcast):
      // Slot identity (not canonical): a search-result row can resolve to a saved
      // podcast whose feedURL differs from the search-row URL. Using slotID keeps
      // the same view instance across that transition; using canonical id would
      // tear down + recreate the view mid-flow. See ListedPodcast.slotID.
      PodcastDetailView(viewModel: PodcastDetailViewModel(listedPodcast: listedPodcast))
        .id(listedPodcast.slotID)
    case .listedEpisode(let listedEpisode, let similarityScore):
      EpisodeDetailView(
        viewModel: EpisodeDetailViewModel(
          listedEpisode: listedEpisode,
          similarityScore: similarityScore
        )
      )
      .id(listedEpisode.id)
    case .unsavedPodcastSeries(let unsavedPodcastSeries):
      PodcastDetailView(
        viewModel: PodcastDetailViewModel(unsavedPodcastSeries: unsavedPodcastSeries)
      )
      .id(unsavedPodcastSeries.id)
    case .searchDiscovery(let viewModel):
      SearchDiscoveryListView(viewModel: viewModel)
        .id("searchDiscovery-\(viewModel.source.stableID)")
    }
  }

  // A destination whose backing row is gone from the mirror (deleted, or not
  // yet loaded at cold launch) pops its tab to the hub. The pop must be
  // deferred — the destination builder runs during the NavigationStack's
  // update pass, and writing the bound path mid-update is undefined behavior.
  // Color.clear rather than EmptyView because .task never fires on EmptyView.
  private func deferredHubPop(_ manager: some ManagingPath, message: Logger.Message) -> some View {
    Color.clear
      .task {
        Self.log.debug(message)
        manager.path = []
      }
  }

  // MARK: - Settings

  var settings = PathManager()

  // MARK: - Settings Navigation

  func showOPMLImport() {
    Self.log.debug("Showing OPML import")

    sheet.dismiss()
    settings.path = [.settingsSection(.opml)]
    currentTab = .settings
  }

  func showTagsSettings() {
    Self.log.debug("Showing tags settings")

    sheet.dismiss()
    settings.path = [.settingsSection(.tags)]
    currentTab = .settings
  }

  // MARK: - Search

  var search = PathManager()

  // MARK: - Search Navigation

  func showSharedUnsavedPodcastSeries(_ unsavedPodcastSeries: UnsavedPodcastSeries) {
    Self.log.debug("Showing searched unsaved series: \(unsavedPodcastSeries.toString)")

    sheet.dismiss()
    search.path = [.unsavedPodcastSeries(unsavedPodcastSeries)]
    currentTab = .search
  }

  func showSearchDiscovery(viewModel: SearchDiscoveryListViewModel) {
    Self.log.debug("Showing search discovery list: \(viewModel.source)")

    sheet.dismiss()
    search.path.append(.searchDiscovery(viewModel))
    currentTab = .search
  }

  func showSharedEpisode(
    unsavedPodcastSeries: UnsavedPodcastSeries,
    unsavedEpisode: UnsavedEpisode,
    startTime: Int? = nil
  ) {
    Self.log.debug("Showing searched episode: \(unsavedEpisode.toString)")

    sheet.dismiss()
    search.path = [
      .unsavedPodcastSeries(unsavedPodcastSeries),
      .episode(
        DisplayedEpisode(
          UnsavedPodcastEpisode(
            unsavedPodcast: unsavedPodcastSeries.unsavedPodcast,
            unsavedEpisode: unsavedEpisode
          )
        ),
        startTime: startTime
      ),
    ]
    currentTab = .search
  }

  // MARK: - On-Deck Episode Detail

  func showOnDeckEpisodeDetail() {
    Self.log.debug("Showing on-deck episode detail sheet")

    currentTab = .upNext
    PlayBar.showOnDeckEpisodeDetail()
  }

  func showPlayBarSheet() {
    Self.log.debug("Showing play bar sheet")

    currentTab = .upNext
    PlayBar.showPlayBarSheet(viewModel: PlayBarViewModel())
  }

  // MARK: - UpNext

  var upNext = PathManager()

  // MARK: - UpNext Navigation

  func showUpNext() {
    Self.log.debug("Showing up next")

    sheet.dismiss()
    currentTab = .upNext
  }

  func dismiss(from tab: Tab? = nil) {
    let targetTab = tab ?? currentTab
    let targetPath: [Destination] =
      switch targetTab {
      case .settings: settings.path
      case .search: search.path
      case .upNext: upNext.path
      case .episodes: episodes.path
      case .podcasts: podcasts.path
      }
    Self.log.debug(
      """
      Dismissing current navigation destination from \(targetTab) \
      with sheetPresented: \(sheet.config != nil), path: \(targetPath)
      """
    )

    if sheet.config != nil {
      sheet.dismiss()
      return
    }

    // Episodes and podcasts tabs always have a root destination entry,
    // so we guard count > 1 to preserve it.
    switch targetTab {
    case .settings:
      guard !settings.path.isEmpty else { return }
      settings.path.removeLast()
    case .search:
      guard !search.path.isEmpty else { return }
      search.path.removeLast()
    case .upNext:
      guard !upNext.path.isEmpty else { return }
      upNext.path.removeLast()
    case .episodes:
      guard episodes.path.count > 1 else { return }
      episodes.path.removeLast()
    case .podcasts:
      guard podcasts.path.count > 1 else { return }
      podcasts.path.removeLast()
    }
  }

  // MARK: - Episodes

  var episodes = PathManager()

  // MARK: - Podcasts

  var podcasts = PathManager()

  // MARK: - Podcast Navigation

  func showPodcastList(_ viewType: PodcastsViewType) {
    Self.log.debug("Showing podcast list: \(viewType)")

    sheet.dismiss()
    podcasts.path = [.podcastsViewType(viewType)]
    currentTab = .podcasts
  }

  func showPodcast(_ podcast: Podcast) {
    Self.log.debug("Showing podcast: \(podcast.toString)")

    sheet.dismiss()
    podcasts.path = [
      .podcastsViewType(podcast.subscribed ? .subscribed : .unsubscribed),
      .podcast(DisplayedPodcast(podcast)),
    ]
    currentTab = .podcasts
  }

  func showEpisode(_ podcastEpisode: PodcastEpisode, startTime: Int? = nil) {
    Self.log.debug("Showing PodcastEpisode: \(podcastEpisode.toString)")

    sheet.dismiss()
    podcasts.path = [
      .podcastsViewType(podcastEpisode.podcast.subscribed ? .subscribed : .unsubscribed),
      .podcast(DisplayedPodcast(podcastEpisode.podcast)),
      .episode(DisplayedEpisode(podcastEpisode), startTime: startTime),
    ]
    currentTab = .podcasts
  }
}
