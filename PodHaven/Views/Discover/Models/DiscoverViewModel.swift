// Copyright Justin Bishop, 2025

import Foundation
import SwiftUI

@Observable @MainActor final class DiscoverViewModel {
  // MARK: - Geometry Management

  var width: CGFloat = 0

  // MARK: - Token / Search Management

  let allTokens: [SearchToken] = SearchToken.allCases
  var currentTokens: [SearchToken]
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

  private let allCategoriesName: String = "All Categories"
  var showCategories: Bool { searchPresented && currentTokens == [.trending] }
  var categories: [String] { [allCategoriesName] + searchedCategories }

  // MARK: - Initialization

  init() {
    currentTokens = [.trending, .category(allCategoriesName)]
  }

  // MARK: - Events

  func categorySelected(_ category: String) {
    currentTokens.append(.category(category))
    _searchText = ""
    updateCurrentView()
  }

  func searchSubmitted() {
    updateCurrentView()
  }

  // MARK: - Private Helpers

  private var searchedCategories: [String] {
    let searchText = searchText.trimmed()
    if searchText.isEmpty { return SearchService.categories }

    return SearchService.categories.filter { $0.lowercased().starts(with: searchText.lowercased()) }
  }

  private func updateCurrentView() {
    if let currentToken = readyToSearch() {
      searchPresented = false
      currentView = currentToken
    }
  }

  private func readyToSearch() -> SearchToken? {
    guard let currentToken = currentTokens.first else { return nil }

    let searchText = searchText.trimmed()
    guard (currentTokens.count == 2) || (currentToken != .trending && !searchText.isEmpty)
    else { return nil }

    return currentToken
  }
}
