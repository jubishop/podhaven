// Copyright Justin Bishop, 2025

import FactoryKit
import Foundation
import Logging

@Observable @MainActor class TrendingCategoryViewModel {
  @ObservationIgnored @DynamicInjected(\.searchService) private var searchService

  private static let log = Log.as(LogSubsystem.SearchView.trending)

  enum State {
    case loading
    case loaded([FeedResultConvertible])
    case error(String)
  }

  let category: String
  private(set) var state: State = .loading

  init(category: String) {
    self.category = category
  }

  func loadPodcasts() async {
    state = .loading

    do {
      let result = try await searchService.searchTrending(categories: [category])
      state = .loaded(result.convertibleFeeds)
    } catch {
      Self.log.error(error)
      state = .error(ErrorKit.message(for: error))
    }
  }
}
