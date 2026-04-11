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

    guard let data = self.data(using: .utf8) else {
      Assert.fatal("Failed to encode string to UTF-8 data")
    }
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

  // MARK: - SHA256

  func sha256() -> String {
    let hexDigits: [Character] = Array("0123456789abcdef")
    return Data(SHA256.hash(data: Data(utf8)))
      .reduce(into: "") { result, byte in
        result.append(hexDigits[Int(byte >> 4)])
        result.append(hexDigits[Int(byte & 0x0F)])
      }
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
