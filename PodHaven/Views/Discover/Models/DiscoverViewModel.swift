// Copyright Justin Bishop, 2025

import Foundation
import SwiftUI

@Observable @MainActor final class DiscoverViewModel {
  let allTokens: [SearchToken] = SearchToken.allCases
  var currentTokens: [SearchToken] = [.trending]
  var currentView: SearchToken = .trending
  var searchText: String = "" {
    didSet {
      if currentTokens.isEmpty && !searchText.trimmed.isEmpty { currentTokens = [.allFields] }
    }
  }

  var searchPresented: Bool = false
  var width: CGFloat = 0

  var showSearchWarning: Bool {
    searchPresented && currentTokens.count == 1 && currentTokens.first != .trending
      && searchText.isEmpty
  }
  var showCategories: Bool { searchPresented && currentTokens == [.trending] }

  func categorySelected(_ category: String) {
    currentTokens.append(.category(category))
    searchPresented = false
  }

  func searchSubmitted() {
    if !searchText.isEmpty {
      searchPresented = false
      currentView = currentTokens.first ?? .allFields
    }
  }
}
