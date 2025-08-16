// Copyright Justin Bishop, 2025

import FactoryKit
import Foundation
import Logging
import SwiftUI

@Observable @MainActor class TrendingCategoryGridViewModel {
  @ObservationIgnored @DynamicInjected(\.searchService) private var searchService

  private static let log = Log.as(LogSubsystem.SearchView.trending)

  enum State {
    case loading
    case loaded(TrendingSearchResult)
    case error(String)
  }

  let category: String
  private(set) var state: State = .loading

  private var _isSelecting = false
  var isSelecting: Bool {
    get { _isSelecting }
    set { withAnimation { _isSelecting = newValue } }
  }

  var podcastList: SelectableListUseCase<UnsavedPodcast, FeedURL>

  init(category: String) {
    self.category = category
    self.podcastList = SelectableListUseCase<UnsavedPodcast, FeedURL>(idKeyPath: \.id)
  }

  func execute() async {
    state = .loading

    do {
      let result = try await searchService.searchTrending(categories: [category])
      state = .loaded(TrendingSearchResult(category: category, result: result))
    } catch {
      Self.log.error(error)
      state = .error(ErrorKit.message(for: error))
    }
  }
}
