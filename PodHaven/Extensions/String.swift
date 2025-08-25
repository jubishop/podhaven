import CryptoKit
import Foundation
import RegexBuilder

extension String {
  // MARK: - Hashing

  private static let hashChars = Array(
    "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789"
  )

  func hash(to length: Int = 8) -> String {
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

  func sha1() -> String {
    Insecure.SHA1.hash(data: Data(self.utf8)).compactMap { String(format: "%02x", $0) }.joined()
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
          // Self-closing tags: <tag/>
          Regex {
            "/>"
          }
          // Opening tags: <tag> (to handle truncated content)
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
