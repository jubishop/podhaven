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

  init(category: String) {
    self.category = category
  }

  func execute() async {
    state = .loading

    do {
      let categories = category == SearchService.allCategories ? [] : [category]
      let result = try await searchService.searchTrending(
        categories: categories,
        language: AppInfo.languageCode
      )
      state = .loaded(TrendingSearchResult(category: category, result: result))
    } catch {
      Self.log.error(error)
      state = .error(ErrorKit.message(for: error))
    }
  }
}
