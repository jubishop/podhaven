import CryptoKit
import Foundation
import RegexBuilder

extension String: Stringable {
  public var toString: String { self.hash() }
}

extension String {
  // MARK: - Hashing

  private static let hashChars = Array(
    "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789"
  )

  func hash(to length: Int = 4) -> String {
    guard length > 0 else { return "" }

    let data = self.data(using: .utf8)!
    let hash = SHA256.hash(data: data)
    let hashData = Data(hash)

    let result = (0..<length)
      .map { i in
        let byte = hashData[i % hashData.count]
        let index = Int(byte) % Self.hashChars.count
        return Self.hashChars[index]
      }

    return String(result)
  }

  // MARK: - Transforming

  func trimmed() -> String {
    self.trimmingCharacters(in: .whitespacesAndNewlines)
  }

  // MARK: - HTML Analysis

  func hasHTMLTags() -> Bool {
    self.contains(
      Regex {
        ChoiceOf {
          // Closing tags: </tag>
          Regex {
            "</"
          }
          // Self-closing tags: <tag/> or <tag />
          Regex {
            "/>"
          }
          // Opening tags with attributes: <tag attr="value"> or <tag class='x'>
          Regex {
            "<"
            OneOrMore(.word)
            OneOrMore {
              CharacterClass.anyOf(" \t\n\r=\"'")
                .union(.word)
            }
            ">"
          }
          // Simple opening tags: <tag>
          Regex {
            "<"
            OneOrMore(.word)
            ">"
          }
        }
      }
    )
  }

  func hasHTMLEntities() -> Bool {
    self.contains(
      Regex {
        ChoiceOf {
          // Named entities: &word;
          Regex {
            "&"
            OneOrMore(.word)
            ";"
          }
          // Numeric entities: &#123;
          Regex {
            "&#"
            OneOrMore(.digit)
            ";"
          }
          // Hex entities: &#x1F;
          Regex {
            "&#x"
            OneOrMore(.hexDigit)
            ";"
          }
        }
      }
    )
  }

  func isHTML() -> Bool {
    hasHTMLTags() || hasHTMLEntities()
  }
}
