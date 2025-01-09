// Copyright Justin Bishop, 2025

import Foundation

@Observable @MainActor final class DiscoverViewModel {
  enum Token: CaseIterable, Identifiable, Hashable {
    case allFields, titles, people, trending
    case category(String)
    var id: Self { self }

    static let allCases: [Token] = [.allFields, .titles, .people, .trending]
    var text: String {
      switch self {
      case .allFields: return "All Fields"
      case .titles: return "Titles"
      case .people: return "People"
      case .trending: return "Trending"
      case .category(let category): return category
      }
    }
  }

  let allTokens: [Token] = Token.allCases
  var currentTokens: [Token] = [.trending]
  var searchText: String = ""

  var showCategories: Bool { currentTokens.count == 1 && currentTokens.first == .trending }
  var width: CGFloat = 0

  func categorySelected(_ category: String) {
    currentTokens.append(.category(category))
  }
}
