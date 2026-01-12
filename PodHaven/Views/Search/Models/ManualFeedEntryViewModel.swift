// Copyright Justin Bishop, 2025

import FactoryKit
import Foundation
import Logging
import Tagged

@Observable @MainActor class ManualFeedEntryViewModel {
  @ObservationIgnored @DynamicInjected(\.shareService) private var shareService
  @ObservationIgnored @DynamicInjected(\.sleeper) private var sleeper

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

  @ObservationIgnored private var previewTask: Task<Void, Never>?

  var canSubmit: Bool {
    !urlText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && !isLoading
  }

  private var isLoading: Bool {
    if case .loading = state { return true }
    return false
  }

  // MARK: - Actions

  private func schedulePreview() {
    previewTask?.cancel()
    previewTask = nil

    let trimmedURL = urlText.trimmingCharacters(in: .whitespacesAndNewlines)

    guard !trimmedURL.isEmpty, let url = URL(string: trimmedURL) else {
      previewState = .idle
      return
    }

    let task = Task { [weak self] in
      guard let self else { return }

      try? await sleeper.sleep(for: Self.previewDebounceDuration)
      guard !Task.isCancelled else { return }

      await fetchPreview(for: FeedURL(url))
    }

    previewTask = task
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
      Self.log.error(error, mundane: .trace)
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

    state = .loading
    do {
      try await shareService.handlePodcastURL(FeedURL(url))
      state = .idle
      urlText = ""
      return true
    } catch {
      Self.log.error(error)
      state = .error(ErrorKit.coreMessage(for: error))
      return false
    }
  }
}
