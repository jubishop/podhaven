// Copyright Justin Bishop, 2025

import FactoryKit
import Foundation

@Observable @MainActor class ManualFeedEntryViewModel {
  @ObservationIgnored @DynamicInjected(\.shareService) private var shareService

  private static let log = Log.as(LogSubsystem.SearchView.manual)

  // MARK: - State

  enum State {
    case idle
    case loading
    case error(String)
  }

  var state: State = .idle
  var urlText: String = ""

  var canSubmit: Bool {
    !urlText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && !isLoading
  }
  private var isLoading: Bool {
    if case .loading = state { return true }
    return false
  }

  // MARK: - Actions

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
