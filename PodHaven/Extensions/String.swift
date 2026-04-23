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

  // MARK: - HTML Stripping / Decoding

  // Replaces each HTML tag with a single space so adjacent tag-separated words
  // don't get glued together. Does not trim or collapse whitespace — callers
  // that care should chain into `trimmed()` or their own whitespace pass.
  func strippingHTMLTags() -> String {
    var result = self
    unsafe result.replace(Self.htmlTagRegex, with: " ")
    return result
  }

  // Decodes named HTML entities (e.g. &amp;, &ndash;), numeric entities
  // (&#8217;), and hex entities (&#x2014;). Named lookups are
  // case-insensitive. Unknown or malformed entities are left unchanged.
  // Runs in-process with no main-thread dependency, unlike
  // NSAttributedString's HTML importer.
  func decodingHTMLEntities() -> String {
    var result = self
    for (entity, replacement) in Self.namedHTMLEntities {
      result = result.replacingOccurrences(
        of: entity,
        with: replacement,
        options: .caseInsensitive
      )
    }
    return Self.decodingNumericHTMLEntities(in: result)
  }

  // Regex<Substring> isn't Sendable-annotated upstream, but its compiled NFA
  // is immutable and matching is thread-safe. Precompile once.
  private nonisolated(unsafe) static let htmlTagRegex = /<[^>]+>/

  private static let namedHTMLEntities: [String: String] = [
    "&amp;": "&",
    "&lt;": "<",
    "&gt;": ">",
    "&quot;": "\"",
    "&apos;": "'",
    "&nbsp;": "\u{00A0}",
    "&#39;": "'",
    "&#x27;": "'",
    "&rsquo;": "'",
    "&lsquo;": "'",
    "&rdquo;": "\"",
    "&ldquo;": "\"",
    "&mdash;": "\u{2014}",
    "&ndash;": "\u{2013}",
    "&hellip;": "\u{2026}",
    "&bull;": "\u{2022}",
    "&deg;": "\u{00B0}",
    "&copy;": "\u{00A9}",
    "&reg;": "\u{00AE}",
    "&trade;": "\u{2122}",
    "&euro;": "\u{20AC}",
    "&pound;": "\u{00A3}",
    "&yen;": "\u{00A5}",
    "&cent;": "\u{00A2}",
    "&sect;": "\u{00A7}",
    "&para;": "\u{00B6}",
    "&middot;": "\u{00B7}",
    "&frac12;": "\u{00BD}",
    "&frac14;": "\u{00BC}",
    "&frac34;": "\u{00BE}",
    "&sup1;": "\u{00B9}",
    "&sup2;": "\u{00B2}",
    "&sup3;": "\u{00B3}",
    "&times;": "\u{00D7}",
    "&divide;": "\u{00F7}",
    "&plusmn;": "\u{00B1}",
  ]

  private static func decodingNumericHTMLEntities(in text: String) -> String {
    var index = text.startIndex
    var output = ""
    output.reserveCapacity(text.count)

    while index < text.endIndex {
      let character = text[index]

      guard character == "&" else {
        output.append(character)
        index = text.index(after: index)
        continue
      }

      let hashIndex = text.index(after: index)
      guard hashIndex < text.endIndex, text[hashIndex] == "#" else {
        output.append(character)
        index = hashIndex
        continue
      }

      var valueStart = text.index(after: hashIndex)
      var isHex = false

      if valueStart < text.endIndex, text[valueStart] == "x" || text[valueStart] == "X" {
        isHex = true
        valueStart = text.index(after: valueStart)
      }

      var cursor = valueStart
      var isValid = true
      while cursor < text.endIndex, text[cursor] != ";" {
        let scalar = text[cursor]
        let isValidDigit = isHex ? scalar.isHexDigit : scalar.isNumber
        if !isValidDigit {
          isValid = false
          break
        }
        cursor = text.index(after: cursor)
      }

      guard cursor < text.endIndex, isValid else {
        output.append("&")
        index = hashIndex
        continue
      }

      let entityRange = index...cursor
      let numberString = String(text[valueStart..<cursor])

      if numberString.isEmpty {
        output.append(contentsOf: text[entityRange])
        index = text.index(after: cursor)
        continue
      }

      let parsedValue = isHex ? Int(numberString, radix: 16) : Int(numberString)

      if let value = parsedValue, let scalar = UnicodeScalar(value) {
        output.unicodeScalars.append(scalar)
      } else {
        output.append(contentsOf: text[entityRange])
      }

      index = text.index(after: cursor)
    }

    return output
  }
}
