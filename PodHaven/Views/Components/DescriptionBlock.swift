// Copyright Justin Bishop, 2026

import Foundation

struct DescriptionBlock: Equatable, Sendable {
  let content: AttributedString
  let continuesOnNextBlock: Bool

  var text: AttributedString {
    let characters = content.characters
    guard continuesOnNextBlock, characters.last?.isNewline == true else { return content }
    // The next row replaces the final line break.
    return AttributedString(content[..<characters.index(before: characters.endIndex)])
  }
}
