// Copyright Justin Bishop, 2025

import Foundation

@Observable @MainActor final class DiscoverViewModel {
  enum Token: String, CaseIterable, Identifiable, Hashable {
    case allFields = "All Fields"
    case titles = "Titles"
    case people = "People"
    case trending = "Trending"
    var id: Self { self }
  }
  let allTokens: [Token] = Token.allCases
  var currentTokens: [Token] = [.trending]
  var showCategories: Bool {
    true
  }
  var searchText: String = ""
  var width: CGFloat = 0

  func categorySelected(_ category: String) {

  }
}
