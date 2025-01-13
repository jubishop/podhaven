// Copyright Justin Bishop, 2025

import Factory
import Foundation
import SwiftUI

@Observable @MainActor final class DiscoverViewModel {
  @ObservationIgnored @Injected(\.alert) private var alert

  // MARK: - Geometry Management

  var width: CGFloat = 0

  // MARK: - Token / Search Management

  let allTokens: [SearchToken] = SearchToken.allCases
  var currentTokens: [SearchToken]
  var currentView: SearchToken = .trending
  var currentCategory: String { currentTokens[safe: 1]?.text ?? allCategoriesName }
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

  // MARK: - Searching and Results

  private let searchService: SearchService
  var trendingResult: TrendingResult?

  // MARK: - Initialization

  init() {
    currentTokens = [.trending, .category(allCategoriesName)]

    let configuration = URLSessionConfiguration.ephemeral
    configuration.allowsCellularAccess = true
    configuration.waitsForConnectivity = true
    let timeout = Double(10)
    configuration.timeoutIntervalForRequest = timeout
    configuration.timeoutIntervalForResource = timeout
    searchService = SearchService(
      session: URLSession(configuration: configuration)
    )
  }

  // MARK: - Events

  func categorySelected(_ category: String) {
    currentTokens.append(.category(category))
    _searchText = ""
    searchSubmitted()
  }

  func searchSubmitted() {
    if let currentToken = readyToSearch() {
      searchPresented = false
      currentView = currentToken
      Task { await runSearch() }
    }
  }

  func runSearch() async {
    self.trendingResult = nil

    do {
      if currentView == .trending {
        self.trendingResult = try await searchTrending()
      }
    } catch {
      alert.andReport(error)
    }
  }

  // MARK: - Private Helpers

  private func searchTrending() async throws -> TrendingResult {
    guard let category = currentTokens[safe: 1], category.text != allCategoriesName
    else { return try await searchService.searchTrending() }
    return try await searchService.searchTrending(categories: [category.text])
  }

  private var searchedCategories: [String] {
    let searchText = searchText.trimmed()
    if searchText.isEmpty { return SearchService.categories }

    return SearchService.categories.filter { $0.lowercased().starts(with: searchText.lowercased()) }
  }

  private func readyToSearch() -> SearchToken? {
    guard let currentToken = currentTokens.first else { return nil }

    let searchText = searchText.trimmed()
    guard (currentTokens.count == 2) || (currentToken != .trending && !searchText.isEmpty)
    else { return nil }

    return currentToken
  }
}
