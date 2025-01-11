// Copyright Justin Bishop, 2025

import Foundation

enum SearchToken: CaseIterable, Identifiable, Hashable, Equatable {
  case allFields, titles, people, trending
  case category(String)
  var id: Self { self }

  static let allCases: [SearchToken] = [.allFields, .titles, .people, .trending]
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
