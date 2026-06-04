// Copyright Justin Bishop, 2026

import Testing

@testable import PodHaven

@Suite("of SearchRecommendationCollector.Source discovery list titles")
struct SearchRecommendationCollectorSourceTests {
  @Test("unbranded Top trending uses 'Top picks' discovery list title")
  func unbrandedTopUsesTopPicksTitle() {
    let source = SearchRecommendationCollector.Source.trending(.init(genreID: nil, title: "Top"))
    #expect(source.discoveryListTitle == "Top picks")
  }

  @Test("branded trending keeps its category title")
  func brandedTrendingKeepsCategoryTitle() {
    let source = SearchRecommendationCollector.Source.trending(
      .init(genreID: 1303, title: "Comedy")
    )
    #expect(source.discoveryListTitle == "Comedy")
  }

  @Test("typed search quotes the query")
  func typedSearchQuotesQuery() {
    let source = SearchRecommendationCollector.Source.search(query: "swift")
    #expect(source.discoveryListTitle == "\"swift\"")
  }
}
