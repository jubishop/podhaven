// Copyright Justin Bishop, 2025

import Factory
import Foundation
import SwiftUI

@Observable @MainActor final class DiscoverViewModel {
  @ObservationIgnored @LazyInjected(\.alert) private var alert
  @ObservationIgnored @LazyInjected(\.playState) private var playState
  @ObservationIgnored @LazyInjected(\.searchService) private var searchService

  // MARK: - Geometry Management

  var width: CGFloat = 0

  // MARK: - Token / Search Management

  let allTokens: [SearchToken] = SearchToken.allCases
  var currentTokens: [SearchToken]
  var currentView: SearchToken = .trending
  var currentCategory: String { currentTokens[safe: 1]?.text ?? Self.allCategoriesName }

  var categoriesToSearch: [String] {
    guard let category = currentTokens[safe: 1], category.text != Self.allCategoriesName
    else { return [] }

    return [category.text]
  }

  static let language: String? = {
    guard let languageCode = Locale.current.language.languageCode, languageCode.isISOLanguage
    else { return nil }

    return languageCode.identifier
  }()

  private var _searchText: String = ""
  var searchText: String {
    get { _searchText }
    set {
      guard currentTokens.count == 1
      else {
        _searchText = ""
        return
      }

      guard let lastToken = currentTokens.last, !lastToken.isCategory
      else {
        _searchText = ""
        return
      }

      _searchText = newValue
    }
  }

  var searchPresented: Bool = false {
    didSet {
      playState.playbarVisible = !searchPresented
    }
  }

  var showSearchWarning: Bool {
    searchPresented
      && currentTokens.count == 1
      && currentTokens.first != .trending
      && searchText.trimmed().isEmpty
  }

  static private let allCategoriesName: String = "All Categories"
  var showCategories: Bool { searchPresented && currentTokens == [.trending] }
  var categories: [String] { [Self.allCategoriesName] + filteredCategories }

  // MARK: - Searching and Results

  var trendingResult: TrendingResult?
  var titleResult: SearchResult?

  // MARK: - Initialization

  init() {
    currentTokens = [.trending, .category(Self.allCategoriesName)]
  }

  func execute() async {
    do {
      try await performSearch()
    } catch {
      alert.andReport(error)
    }
  }

  // MARK: - Events

  func categorySelected(_ category: String) {
    guard currentTokens == [.trending]
    else { return }

    currentTokens.append(.category(category))
    _searchText = ""

    searchSubmitted()
  }

  func searchSubmitted() {
    if currentTokens.isEmpty {
      currentTokens = [.allFields]
    }

    if let firstToken = currentTokens.first, firstToken.isCategory {
      currentTokens.insert(.trending, at: 0)
    }

    if let lastToken = currentTokens.last, lastToken.isCategory {
      _searchText = ""
    }

    if let currentToken = readyToSearch() {
      searchPresented = false
      currentView = currentToken
      Task {
        do {
          try await performSearch()
        } catch {
          alert.andReport(error)
        }
      }
    }
  }

  // MARK: - Private Helpers

  private func performSearch() async throws {
    self.trendingResult = nil

    if currentView == .trending {
      self.trendingResult = try await searchTrending()
    } else if currentView == .titles {
      self.titleResult = try await searchByTitle()
    }
  }

  private func searchTrending() async throws -> TrendingResult {
    try await searchService.searchTrending(categories: categoriesToSearch, language: Self.language)
  }

  private func searchByTitle() async throws -> SearchResult {
    try await searchService.searchByTitle(searchText)
  }

  private var filteredCategories: [String] {
    let searchText = searchText.trimmed()
    if searchText.isEmpty { return SearchService.categories }
    return SearchService.categories.filter { $0.lowercased().starts(with: searchText.lowercased()) }
  }

  private func readyToSearch() -> SearchToken? {
    let searchText = searchText.trimmed()

    guard let currentToken = currentTokens.first
    else { return searchText.isEmpty ? nil : .allFields }

    guard (currentTokens.count == 2) || (currentToken != .trending && !searchText.isEmpty)
    else { return nil }

    if currentToken.isCategory { return nil }

    return currentToken
  }
}
