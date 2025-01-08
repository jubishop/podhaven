// Copyright Justin Bishop, 2025

import Foundation

@Observable @MainActor final class DiscoverViewModel {
  struct Token: Identifiable, Hashable {
    var id: String { token.rawValue }
    var text: String { token.rawValue }
    private let token: TokenEnum
    init(_ token: TokenEnum) { self.token = token }
  }

  enum TokenEnum: String, CaseIterable {
    case allFields = "All Fields"
    case titles = "Titles"
    case people = "People"
    case trending = "Trending"

    var token: Token { Token(self) }
    static var all: [Token] { TokenEnum.allCases.map(\.token) }
  }

  let allTokens = TokenEnum.all
  var currentTokens: [Token] = [Token(.trending)]
  var showCategories: Bool {
    true
  }
  var searchText: String = ""
  var width: CGFloat = 0

  func categorySelected(_ category: String) {

  }
}
