// Copyright Justin Bishop, 2025

import SwiftUI

// Parses a small HTML subset into an AttributedString with lossy preprocessing.
// Lists become bullets/numbered lines, block tags become newlines, entities are
// decoded. Pure and nonisolated so the work runs off the main actor.
enum HTMLContent {
  // MARK: - Description Builder

  // Builds the full episode-description AttributedString off the main actor:
  // the same output as `attributedString`, plus timestamp tokens turned into
  // tappable links the detail view intercepts via openURL. Unlike
  // `attributedString` it never returns nil for plain text, so timestamps in
  // entity/tag-free descriptions still link.
  @concurrent
  static func descriptionAttributedString(html: String, font: Font) async -> AttributedString? {
    guard !html.isEmpty else { return nil }
    var result = attributedString(html: html, font: font) ?? AttributedString(html)
    applyTimestampLinks(to: &result)
    return result
  }

  private static func applyTimestampLinks(to attributed: inout AttributedString) {
    let plainText = String(attributed.characters)
    guard plainText.contains(":") else { return }

    let matches = unsafe plainText.matches(of: Timestamp.regex)
    for match in matches {
      guard let url = Timestamp.url(for: plainText[match.range]) else { continue }

      let characters = attributed.characters
      let lowerOffset = plainText.distance(from: plainText.startIndex, to: match.range.lowerBound)
      let length = plainText.distance(from: match.range.lowerBound, to: match.range.upperBound)
      let lowerBound = characters.index(characters.startIndex, offsetBy: lowerOffset)
      let upperBound = characters.index(lowerBound, offsetBy: length)
      let linkRange = lowerBound..<upperBound

      guard attributed[linkRange].link == nil else { continue }
      attributed[linkRange].link = url
      attributed[linkRange].foregroundColor = .accentColor
    }
  }

  // MARK: - Main Parsing

  static func attributedString(html: String, font: Font) -> AttributedString? {
    guard html.isHTML() else {
      let decoded = html.decodingHTMLEntities()
      let linked = autodetectedLinks(in: AttributedString(decoded))
      let foundLink = linked.runs.contains { $0.link != nil }
      guard decoded != html || foundLink else { return nil }
      return linked
    }

    let cleanedHTML = preprocessHTML(html)
    let textParts = parseTextParts(cleanedHTML)

    return autodetectedLinks(in: buildAttributedString(from: textParts, baseFont: font))
  }

  // MARK: - HTML Preprocessing

  private static func preprocessHTML(_ htmlString: String) -> String {
    var result = htmlString
    result = handleListTags(result)
    result = handleBlockTags(result)
    result = handleParagraphTags(result)
    result = handleLineBreaks(result)
    result = cleanupWhitespace(result)
    return result
  }

  private static func handleListTags(_ text: String) -> String {
    var output = ""
    output.reserveCapacity(text.count)
    var index = text.startIndex
    var listStack: [ListKind] = []
    var orderedCounts: [Int] = []

    func appendNewlineIfNeeded() {
      if let last = output.last, last != "\n" {
        output.append("\n")
      }
    }

    while index < text.endIndex {
      if text[index] == "<", let tagEnd = text[index...].firstIndex(of: ">") {
        let tagString = String(text[index...tagEnd])
        if let listTag = ListTag(tagString: tagString) {
          switch listTag {
          case .unorderedOpen:
            listStack.append(.unordered)
            orderedCounts.append(0)
            appendNewlineIfNeeded()
          case .unorderedClose:
            if !listStack.isEmpty {
              listStack.removeLast()
              orderedCounts.removeLast()
            }
            appendNewlineIfNeeded()
          case .orderedOpen:
            listStack.append(.ordered)
            orderedCounts.append(0)
            appendNewlineIfNeeded()
          case .orderedClose:
            if !listStack.isEmpty {
              listStack.removeLast()
              orderedCounts.removeLast()
            }
            appendNewlineIfNeeded()
          case .itemOpen:
            if let last = output.last, last != "\n" {
              output.append("\n")
            }
            let listKind = listStack.last
            if listKind == .ordered {
              let next = (orderedCounts.popLast() ?? 0) + 1
              orderedCounts.append(next)
              output.append("\(next). ")
            } else {
              output.append("• ")
            }
          case .itemClose:
            appendNewlineIfNeeded()
          }

          index = text.index(after: tagEnd)
          continue
        }
      }

      output.append(text[index])
      index = text.index(after: index)
    }

    return output
  }

  private static func handleBlockTags(_ text: String) -> String {
    text
      .replacingOccurrences(
        of: "<(div|h[1-6]|section|article|header|footer|blockquote)[^>]*>",
        with: "\n",
        options: [.regularExpression, .caseInsensitive]
      )
      .replacingOccurrences(
        of: "</(div|h[1-6]|section|article|header|footer|blockquote)>",
        with: "\n",
        options: [.regularExpression, .caseInsensitive]
      )
  }

  private static func handleParagraphTags(_ text: String) -> String {
    var result = text
    result = result.replacingOccurrences(of: "</p>", with: "\n", options: .caseInsensitive)
    result = result.replacingOccurrences(
      of: "^\\s*<p[^>]*>",
      with: "",
      options: [.regularExpression, .caseInsensitive]
    )
    result = result.replacingOccurrences(
      of: "<p[^>]*>",
      with: "\n",
      options: [.regularExpression, .caseInsensitive]
    )
    return result
  }

  private static func handleLineBreaks(_ text: String) -> String {
    text.replacingOccurrences(
      of: "<br\\s*/?\\s*>",
      with: "\n",
      options: [.regularExpression, .caseInsensitive]
    )
  }

  private static func cleanupWhitespace(_ text: String) -> String {
    text
      .replacingOccurrences(of: "\n[ \t]+", with: "\n", options: .regularExpression)
      .replacingOccurrences(of: "[ \t]+\n", with: "\n", options: .regularExpression)
      .replacingOccurrences(of: "\n{3,}", with: "\n\n", options: .regularExpression)
      .trimmingCharacters(in: .whitespacesAndNewlines)
  }

  // MARK: - Text Parsing

  private static func parseTextParts(_ text: String) -> [TextPart] {
    var parts: [TextPart] = []
    var currentText = ""
    let formatStack = FormatStack()

    var index = text.startIndex

    while index < text.endIndex {
      if text[index] == "<" {
        if !currentText.isEmpty {
          parts.append(TextPart(text: currentText, format: formatStack.current))
          currentText = ""
        }

        if let (tagEnd, tag) = parseTag(from: text, startingAt: index) {
          formatStack.processTag(tag)
          index = text.index(after: tagEnd)
        } else {
          // Malformed tag, treat as text
          currentText.append(text[index])
          index = text.index(after: index)
        }
      } else {
        currentText.append(text[index])
        index = text.index(after: index)
      }
    }

    if !currentText.isEmpty {
      parts.append(TextPart(text: currentText, format: formatStack.current))
    }

    return parts
  }

  private static func parseTag(from text: String, startingAt index: String.Index) -> (
    String.Index, HTMLTag
  )? {
    guard let tagEnd = text[index...].firstIndex(of: ">") else { return nil }

    let tagString = String(text[index...tagEnd])
    let tag = HTMLTag(tagString: tagString)

    return (tagEnd, tag)
  }

  // MARK: - AttributedString Building

  private static func buildAttributedString(from parts: [TextPart], baseFont: Font)
    -> AttributedString
  {
    var result = AttributedString()

    for part in parts where !part.text.isEmpty {
      let decodedText = part.text.decodingHTMLEntities()
      let attributedPart = Self.styledAttributedString(
        decodedText,
        format: part.format,
        baseFont: baseFont
      )
      result.append(attributedPart)
    }

    return result
  }

  // Links bare http(s) URLs that aren't already inside an anchor. Restricted to
  // text that literally begins with the scheme so bare domains (README.md) and
  // emails stay untouched; NSDataDetector handles the URL boundary (trailing
  // punctuation, balanced parens) better than a hand-rolled pattern.
  private static func autodetectedLinks(in attributedString: AttributedString) -> AttributedString {
    let plainText = String(attributedString.characters)
    guard plainText.range(of: "http", options: .caseInsensitive) != nil else {
      return attributedString
    }

    let fullRange = NSRange(plainText.startIndex..<plainText.endIndex, in: plainText)
    let matches = linkDetector.matches(in: plainText, options: [], range: fullRange)
    guard !matches.isEmpty else { return attributedString }

    var result = attributedString
    for match in matches {
      guard let url = match.url, let textRange = Range(match.range, in: plainText) else { continue }

      let leading = plainText[textRange].prefix(8).lowercased()
      guard leading.hasPrefix("http://") || leading.hasPrefix("https://") else { continue }

      let characters = result.characters
      let lowerOffset = plainText.distance(from: plainText.startIndex, to: textRange.lowerBound)
      let length = plainText.distance(from: textRange.lowerBound, to: textRange.upperBound)
      let lowerBound = characters.index(characters.startIndex, offsetBy: lowerOffset)
      let upperBound = characters.index(lowerBound, offsetBy: length)
      let linkRange = lowerBound..<upperBound

      guard result[linkRange].link == nil else { continue }
      result[linkRange].link = url
    }

    return result
  }

  private static let linkDetector: NSDataDetector = {
    do {
      return try NSDataDetector(types: NSTextCheckingResult.CheckingType.link.rawValue)
    } catch {
      Assert.fatal("Failed to create link NSDataDetector: \(error)")
    }
  }()

  private static func styledAttributedString(
    _ text: String,
    format: TextFormat,
    baseFont: Font
  ) -> AttributedString {
    var attributedString = AttributedString(text)
    var resolvedFont = baseFont

    if format.isBold {
      resolvedFont = resolvedFont.weight(.bold)
    }

    if format.isItalic {
      resolvedFont = resolvedFont.italic()
    }

    attributedString.font = resolvedFont

    if let linkURL = format.linkURL {
      attributedString.link = linkURL
    }

    if format.isUnderlined {
      attributedString.underlineStyle = .single
    }

    if format.isStrikethrough {
      attributedString.strikethroughStyle = .single
    }

    if format.isMarked {
      attributedString.backgroundColor = Color.yellow.opacity(0.3)
    }

    if format.isItalic {
      attributedString[AttributeScopes.UIKitAttributes.ObliquenessAttribute.self] = 0.2
    }

    return attributedString
  }

  // MARK: - Supporting Types

  private struct TextPart {
    let text: String
    let format: TextFormat
  }

  private struct TextFormat: Equatable {
    let isBold: Bool
    let isItalic: Bool
    let isUnderlined: Bool
    let isStrikethrough: Bool
    let isMarked: Bool
    let linkURL: URL?

    static let plain = TextFormat(
      isBold: false,
      isItalic: false,
      isUnderlined: false,
      isStrikethrough: false,
      isMarked: false,
      linkURL: nil
    )
  }

  private enum ListKind {
    case unordered
    case ordered
  }

  private enum ListTag {
    case unorderedOpen
    case unorderedClose
    case orderedOpen
    case orderedClose
    case itemOpen
    case itemClose

    init?(tagString: String) {
      let trimmed = tagString.trimmingCharacters(in: .whitespacesAndNewlines)
      guard
        let parsed = HTMLContent.parseTagName(from: trimmed)
      else {
        return nil
      }

      let name = parsed.name
      let isClosing = parsed.isClosing

      switch name {
      case "ul":
        self = isClosing ? .unorderedClose : .unorderedOpen
      case "ol":
        self = isClosing ? .orderedClose : .orderedOpen
      case "li":
        self = isClosing ? .itemClose : .itemOpen
      default:
        return nil
      }
    }
  }

  private class FormatStack {
    private var boldCount = 0
    private var italicCount = 0
    private var underlineCount = 0
    private var strikeCount = 0
    private var markCount = 0
    private var linkStack: [URL] = []

    var current: TextFormat {
      TextFormat(
        isBold: boldCount > 0,
        isItalic: italicCount > 0,
        isUnderlined: underlineCount > 0,
        isStrikethrough: strikeCount > 0,
        isMarked: markCount > 0,
        linkURL: linkStack.last
      )
    }

    func processTag(_ tag: HTMLTag) {
      switch tag {
      case .boldOpen, .strongOpen:
        boldCount += 1
      case .boldClose, .strongClose:
        boldCount = max(0, boldCount - 1)
      case .italicOpen, .emOpen:
        italicCount += 1
      case .italicClose, .emClose:
        italicCount = max(0, italicCount - 1)
      case .underlineOpen:
        underlineCount += 1
      case .underlineClose:
        underlineCount = max(0, underlineCount - 1)
      case .strikeOpen, .sOpen, .delOpen:
        strikeCount += 1
      case .strikeClose, .sClose, .delClose:
        strikeCount = max(0, strikeCount - 1)
      case .markOpen:
        markCount += 1
      case .markClose:
        markCount = max(0, markCount - 1)
      case .anchorOpen(let url):
        if let url {
          linkStack.append(url)
        }
      case .anchorClose:
        if !linkStack.isEmpty {
          linkStack.removeLast()
        }
      case .unknown:
        break
      }
    }
  }

  private enum HTMLTag {
    case boldOpen, boldClose
    case strongOpen, strongClose
    case italicOpen, italicClose
    case emOpen, emClose
    case underlineOpen, underlineClose
    case strikeOpen, strikeClose
    case sOpen, sClose
    case delOpen, delClose
    case markOpen, markClose
    case anchorOpen(URL?)
    case anchorClose
    case unknown

    init(tagString: String) {
      let trimmed = tagString.trimmingCharacters(in: .whitespacesAndNewlines)

      guard let parsed = HTMLContent.parseTagName(from: trimmed) else {
        self = .unknown
        return
      }

      let name = parsed.name
      let isClosing = parsed.isClosing

      switch name {
      case "b":
        self = isClosing ? .boldClose : .boldOpen
      case "strong":
        self = isClosing ? .strongClose : .strongOpen
      case "i":
        self = isClosing ? .italicClose : .italicOpen
      case "em":
        self = isClosing ? .emClose : .emOpen
      case "u":
        self = isClosing ? .underlineClose : .underlineOpen
      case "strike":
        self = isClosing ? .strikeClose : .strikeOpen
      case "s":
        self = isClosing ? .sClose : .sOpen
      case "del":
        self = isClosing ? .delClose : .delOpen
      case "mark":
        self = isClosing ? .markClose : .markOpen
      case "a":
        if isClosing {
          self = .anchorClose
        } else {
          let url = Self.extractHref(from: trimmed)
          self = .anchorOpen(url)
        }
      default:
        self = .unknown
      }
    }

    private static func extractHref(from tagString: String) -> URL? {
      let nsRange = NSRange(tagString.startIndex..<tagString.endIndex, in: tagString)
      for regex in hrefRegexes {
        if let match = regex.firstMatch(in: tagString, options: [], range: nsRange),
          let hrefRange = Range(match.range(at: 1), in: tagString)
        {
          let urlString = String(tagString[hrefRange])
          return URL(string: urlString)
        }
      }

      return nil
    }

    private static let hrefRegexes: [NSRegularExpression] = {
      let patterns = [
        #"href\s*=\s*"([^"]+)""#,
        #"href\s*=\s*'([^']+)'"#,
      ]
      return patterns.map {
        do {
          return try NSRegularExpression(pattern: $0, options: [.caseInsensitive])
        } catch {
          Assert.fatal("Failed to compile hardcoded regex pattern '\($0)': \(error)")
        }
      }
    }()
  }

  private static func parseTagName(from tagString: String) -> (
    name: String,
    isClosing: Bool
  )? {
    guard tagString.hasPrefix("<"), tagString.hasSuffix(">") else { return nil }
    var content = tagString.dropFirst().dropLast().trimmingCharacters(in: .whitespacesAndNewlines)
    let isClosing = content.hasPrefix("/")
    if isClosing {
      content = content.dropFirst().trimmingCharacters(in: .whitespacesAndNewlines)
    }

    if content.hasSuffix("/") {
      return nil
    }

    guard let namePart = content.split(whereSeparator: { $0.isWhitespace || $0 == "/" }).first
    else {
      return nil
    }

    return (name: namePart.lowercased(), isClosing: isClosing)
  }

}
