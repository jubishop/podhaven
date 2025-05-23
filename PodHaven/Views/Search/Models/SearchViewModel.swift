// Copyright Justin Bishop, 2025

import FactoryKit
import Foundation
import Logging
import SwiftUI

@Observable @MainActor final class SearchViewModel {
  @ObservationIgnored @DynamicInjected(\.alert) private var alert
  @ObservationIgnored @DynamicInjected(\.playState) private var playState
  @ObservationIgnored @DynamicInjected(\.searchService) private var searchService

  private let log = Log.as(LogSubsystem.SearchView.main)

  // MARK: - Geometry Management

  var width: CGFloat = 0

  // MARK: - Token / Search Management

  let allTokens: [SearchToken] = SearchToken.allCases
  var currentTokens: [SearchToken]
  private(set) var currentView: SearchToken = .trending
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

  var searchPresented: Bool = false

  var showSearchWarning: Bool {
    searchPresented
      && currentTokens.count == 1
      && currentTokens.first != .trending
      && searchText.trimmed().isEmpty
  }

  private static let allCategoriesName: String = "All Categories"
  var showCategories: Bool { searchPresented && currentTokens == [.trending] }
  var categories: [String] { [Self.allCategoriesName] + filteredCategories }

  // MARK: - Searching and Results

  var podcastSearchResult: PodcastSearchResult = PodcastSearchResult(searchText: allCategoriesName)
  var personSearchResult = PersonSearchResult()

  // MARK: - Initialization

  init() {
    currentTokens = [.trending, .category(Self.allCategoriesName)]
  }

  func execute() async {
    do {
      try await performSearch(currentView)
    } catch {
      if ErrorKit.baseError(for: error) is CancellationError { return }
      guard ErrorKit.isRemarkable(error) else {
        log.info(ErrorKit.loggableMessage(for: error))
        return
      }

      log.error(error)
      alert(ErrorKit.message(for: error))
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
      Task { [weak self] in
        guard let self else { return }
        do {
          async let search: Void = performSearch(currentToken)
          currentView = currentToken
          try await search
        } catch let error as SearchError {
          if ErrorKit.baseError(for: error) is CancellationError { return }
          guard ErrorKit.isRemarkable(error) else {
            log.info(ErrorKit.loggableMessage(for: error))
            return
          }

          log.error(error)
          alert(ErrorKit.message(for: error))
        }
      }
    }
  }

  // MARK: - Private Helpers

  private func performSearch(_ currentToken: SearchToken) async throws(SearchError) {
    switch currentToken {
    case .trending:
      try await searchTrending(currentCategory)
    case .titles:
      try await searchByTitle(searchText)
    case .allFields:
      try await searchByTerm(searchText)
    case .people:
      try await searchByPerson(searchText)
    case .category(_):
      Assert.fatal("Trying to perform search on category?")
    }
  }

  private func searchTrending(_ currentCategory: String) async throws(SearchError) {
    self.podcastSearchResult = PodcastSearchResult(searchText: currentCategory)
    self.podcastSearchResult = PodcastSearchResult(
      searchText: currentCategory,
      result: try await searchService.searchTrending(
        categories: categoriesToSearch,
        language: Self.language
      )
    )
  }

  private func searchByTitle(_ searchText: String) async throws(SearchError) {
    self.podcastSearchResult = PodcastSearchResult(searchText: searchText)
    self.podcastSearchResult = PodcastSearchResult(
      searchText: searchText,
      result: try await searchService.searchByTitle(searchText)
    )
  }

  private func searchByTerm(_ searchText: String) async throws(SearchError) {
    self.podcastSearchResult = PodcastSearchResult(searchText: searchText)
    self.podcastSearchResult = PodcastSearchResult(
      searchText: searchText,
      result: try await searchService.searchByTerm(searchText)
    )
  }

  private func searchByPerson(_ searchText: String) async throws(SearchError) {
    self.personSearchResult = PersonSearchResult(searchText: searchText)
    self.personSearchResult = PersonSearchResult(
      searchText: searchText,
      personResult: try await searchService.searchByPerson(searchText)
    )
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
