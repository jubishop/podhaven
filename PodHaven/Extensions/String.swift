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
    guard contains("&") else { return self }

    var output = ""
    output.reserveCapacity(count)
    var index = startIndex

    while index < endIndex {
      guard self[index] == "&" else {
        output.append(self[index])
        index = self.index(after: index)
        continue
      }

      var cursor = self.index(after: index)
      while cursor < endIndex, self[cursor] != ";", self[cursor] != "&" {
        cursor = self.index(after: cursor)
      }

      guard cursor < endIndex, self[cursor] == ";" else {
        output.append("&")
        index = self.index(after: index)
        continue
      }

      let entityRange = index...cursor
      let entity = self[entityRange]
      if let replacement = Self.htmlEntityReplacement(for: entity) {
        let nextIndex = self.index(after: cursor)
        if replacement == "&",
          let nested = Self.numericHTMLEntityReplacement(in: self, startingAt: nextIndex)
        {
          output.append(contentsOf: nested.replacement)
          index = nested.endIndex
          continue
        }
        output.append(contentsOf: replacement)
      } else {
        output.append(contentsOf: entity)
      }
      index = self.index(after: cursor)
    }

    return output
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

  private static func htmlEntityReplacement(for entity: Substring) -> String? {
    let normalized = entity.lowercased()
    if let replacement = namedHTMLEntities[normalized] {
      return replacement
    }

    guard normalized.hasPrefix("&#"), normalized.hasSuffix(";") else { return nil }
    var number = normalized.dropFirst(2).dropLast()
    let radix: Int
    if number.first == "x" {
      radix = 16
      number = number.dropFirst()
    } else {
      radix = 10
    }
    let validDigits = radix == 16 ? "0123456789abcdef" : "0123456789"
    guard !number.isEmpty,
      number.allSatisfy(validDigits.contains),
      let value = Int(number, radix: radix),
      let scalar = UnicodeScalar(value)
    else { return nil }
    return String(scalar)
  }

  private static func numericHTMLEntityReplacement(
    in text: String,
    startingAt index: String.Index
  ) -> (replacement: String, endIndex: String.Index)? {
    guard index < text.endIndex, text[index] == "#" else { return nil }
    var cursor = text.index(after: index)
    while cursor < text.endIndex, text[cursor] != ";", text[cursor] != "&" {
      cursor = text.index(after: cursor)
    }
    guard cursor < text.endIndex, text[cursor] == ";" else { return nil }

    let candidate = "&" + text[index...cursor]
    guard let replacement = htmlEntityReplacement(for: candidate[...]) else { return nil }
    return (replacement, text.index(after: cursor))
  }
}
