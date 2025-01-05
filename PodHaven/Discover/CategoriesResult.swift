// Copyright Justin Bishop, 2025

import Foundation

struct CategoriesResult: Sendable, Decodable {
  struct Category: Sendable, Decodable {
    let id: Int
    let name: String
  }
  let feeds: [Category]
  let count: Int
}

