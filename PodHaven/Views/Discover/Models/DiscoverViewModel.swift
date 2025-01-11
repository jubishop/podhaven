// Copyright Justin Bishop, 2025

import Foundation
import SwiftUI

@Observable @MainActor final class DiscoverViewModel {
  // MARK: - Geometry Management

  var width: CGFloat = 0

  // MARK: - Token / Search Management

  let allTokens: [SearchToken] = SearchToken.allCases
  var currentTokens: [SearchToken] = [.trending]
  var currentView: SearchToken = .trending

  var searchText: String = "" {
    didSet {
      if currentTokens.isEmpty && !searchText.trimmed().isEmpty {
        currentTokens = [.allFields]
      } else if currentTokens.count == 2 {
        _searchText = ""
      } else if currentTokens == [.trending] {
        let searchedCategories = searchedCategories
        if searchedCategories.count == 1 {
          if let onlyCategory = searchedCategories.first {
            categorySelected(onlyCategory)
          }
        }
      }
    }
  }

  var searchPresented: Bool = false {
    didSet {
      PlayState.shared.playbarVisible = !searchPresented
    }
  }

  var showSearchWarning: Bool {
    searchPresented && currentTokens.count == 1 && currentTokens.first != .trending
      && searchText.trimmed().isEmpty
  }

  var showCategoryWarning: Bool {
    currentTokens.count == 2 && !searchText.trimmed().isEmpty
  }
  var showCategories: Bool { searchPresented && currentTokens == [.trending] }

  private var searchedCategories: [String] {
    let searchText = self.searchText.trimmed()
    if searchText.isEmpty { return SearchService.categories }

    return SearchService.categories.filter { $0.lowercased().starts(with: searchText.lowercased()) }
  }
  var categories: [String] { ["All Categories"] + searchedCategories }

  // MARK: - Events

  func categorySelected(_ category: String) {
    currentTokens.append(.category(category))
    _searchText = ""
    searchPresented = false
    updateCurrentView()
  }

  func searchSubmitted() {
    // TODO: Deal with .trending but no category chosen
    if !searchText.isEmpty {
      searchPresented = false
      updateCurrentView()
    }
  }

  // MARK: - Private Helpers

  private func updateCurrentView() {
    currentView = currentTokens.first ?? .allFields
  }
}
