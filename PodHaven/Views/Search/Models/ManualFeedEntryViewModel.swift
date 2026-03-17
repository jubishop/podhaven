// Copyright Justin Bishop, 2025

import FactoryKit
import Foundation
import Logging
import Tagged

@Observable @MainActor class ManualFeedEntryViewModel {
  @ObservationIgnored @DynamicInjected(\.shareService) private var shareService
  private static let log = Log.as(LogSubsystem.SearchView.manual)

  // MARK: - Configuration

  private static let previewDebounceDuration: Duration = .milliseconds(500)

  // MARK: - State

  enum LoadingState {
    case idle
    case loading
    case error(String)
  }

  struct PodcastPreview {
    let image: URL
    let title: String
    let mostRecentPostDate: Date?
    let episodeCount: Int
  }

  enum PreviewState {
    case idle
    case loading
    case loaded(PodcastPreview)
    case error(String)
  }

  var state: LoadingState = .idle
  var previewState: PreviewState = .idle
  var urlText: String = "" {
    didSet {
      if urlText != oldValue {
        schedulePreview()
      }
    }
  }

  @ObservationIgnored private lazy var debouncePreview = Debounce(
    duration: Self.previewDebounceDuration
  )

  var canSubmit: Bool {
    !urlText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && !isLoading
  }

  private var isLoading: Bool {
    if case .loading = state { return true }
    return false
  }

  // MARK: - Actions

  private func schedulePreview() {
    let trimmedURL = urlText.trimmingCharacters(in: .whitespacesAndNewlines)

    guard !trimmedURL.isEmpty, let url = URL(string: trimmedURL) else {
      debouncePreview.cancel()
      previewState = .idle
      return
    }

    let feedURL: FeedURL
    do {
      feedURL = try FeedURL(url).convertToHTTPSURL()
    } catch {
      debouncePreview.cancel()
      previewState = .idle
      return
    }

    debouncePreview { [weak self] in
      guard let self else { return }
      await fetchPreview(for: feedURL)
    }
  }

  private func fetchPreview(for feedURL: FeedURL) async {
    previewState = .loading

    do {
      let feed = try await PodcastFeed.parse(feedURL)
      try Task.checkCancellation()

      let unsavedPodcast = try feed.toUnsavedPodcast()
      let unsavedEpisodeArray = feed.toUnsavedEpisodes()

      let preview = PodcastPreview(
        image: unsavedPodcast.image,
        title: unsavedPodcast.title,
        mostRecentPostDate: unsavedEpisodeArray.first?.pubDate,
        episodeCount: unsavedEpisodeArray.count
      )

      previewState = .loaded(preview)
    } catch {
      Self.log.caughtError("fetchPreview: failed for \(feedURL)", error)
      guard !Task.isCancelled else { return }
      previewState = .error("Failed to load preview")
    }
  }

  @discardableResult
  func submitURL() async -> Bool {
    let trimmedURL = urlText.trimmingCharacters(in: .whitespacesAndNewlines)

    guard !trimmedURL.isEmpty else {
      state = .error("Please enter a feed URL")
      return false
    }

    guard let url = URL(string: trimmedURL) else {
      state = .error("Please enter a valid URL")
      return false
    }

    let feedURL: FeedURL
    do {
      feedURL = try FeedURL(url).convertToHTTPSURL()
    } catch {
      Self.log.caughtError("submitURL: invalid URL '\(trimmedURL)'", error)
      state = .error("Please enter a valid URL")
      return false
    }

    state = .loading
    do {
      try await shareService.handlePodcastURL(feedURL)
      state = .idle
      urlText = ""
      return true
    } catch {
      Self.log.caughtError("submitURL: failed for \(url)", error)
      state = .error(ErrorKit.message(for: error))
      return false
    }
  }
}
