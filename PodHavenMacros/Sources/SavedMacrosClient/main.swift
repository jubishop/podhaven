// Copyright Justin Bishop, 2025

import SavedMacros
import Tagged

protocol Savable {}

@Saved<UnsavedExample>
struct Example {
  // The macro will generate:
  // typealias ID = Tagged<Self, Int64>
  // var id: ID
  // var unsaved: UnsavedExample
  // init(id: ID, from unsaved: UnsavedExample) { ... }
}

struct UnsavedExample: Savable {}
