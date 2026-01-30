// Copyright Justin Bishop, 2025

import SwiftUI

struct HTMLText: View {
  @Environment(\.font) private var environmentFont

  private let html: String
  private let menuConfig: MenuConfig?

  init(_ html: String) {
    self.html = html
    self.menuConfig = nil
  }

  init<Content: View>(
    _ html: String,
    menuMatching pattern: Regex<Substring>,
    menuValidator: ((String, String.Index) -> Bool)? = nil,
    @ViewBuilder menuContent: @escaping (String) -> Content
  ) {
    self.html = html
    self.menuConfig = MenuConfig(
      pattern: pattern,
      validator: menuValidator,
      content: { AnyView(menuContent($0)) }
    )
  }

  var body: some View {
    if let menuConfig {
      menuBody(menuConfig)
    } else {
      standardBody
    }
  }

  @ViewBuilder
  private var standardBody: some View {
    let attributedString = Self.buildAttributedString(html: html, font: environmentFont ?? .body)
    if let attributedString {
      Text(attributedString)
    } else {
      Text(html)
    }
  }

  // MARK: - Main Parsing

  private static func buildAttributedString(html: String, font: Font) -> AttributedString? {
    guard html.isHTML() else { return nil }

    let cleanedHTML = preprocessHTML(html)
    let textParts = parseTextParts(cleanedHTML)

    return buildAttributedString(from: textParts, baseFont: font)
  }

  // MARK: - HTML Preprocessing

  static func preprocessHTML(_ htmlString: String) -> String {
    var result = htmlString

    // Handle list tags
    result = handleListTags(result)

    // Handle paragraph tags with intelligent spacing
    result = handleParagraphTags(result)

    // Handle line breaks
    result = handleLineBreaks(result)

    // Clean up whitespace
    result = cleanupWhitespace(result)

    return result
  }

  private static func handleListTags(_ text: String) -> String {
    var result = text

    // Strip <ul> tags (with newlines for spacing)
    result = result.replacingOccurrences(of: "</ul>", with: "\n", options: .caseInsensitive)
    result = result.replacingOccurrences(
      of: "<ul[^>]*>",
      with: "\n",
      options: [.regularExpression, .caseInsensitive]
    )

    // Convert list items: opening tag becomes bullet, closing tag becomes newline
    result = result.replacingOccurrences(
      of: "<li[^>]*>",
      with: "• ",
      options: [.regularExpression, .caseInsensitive]
    )
    result = result.replacingOccurrences(of: "</li>", with: "\n", options: .caseInsensitive)

    return result
  }

  private static func handleParagraphTags(_ text: String) -> String {
    var result = text

    // Replace closing paragraphs with newlines
    result = result.replacingOccurrences(of: "</p>", with: "\n", options: .caseInsensitive)

    // Remove leading <p> tag (with or without attributes) at start of text
    result = result.replacingOccurrences(
      of: "^\\s*<p[^>]*>",
      with: "",
      options: [.regularExpression, .caseInsensitive]
    )

    // Replace all remaining <p> tags (with or without attributes) with newlines
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

  internal static func decodeHTMLEntities(_ text: String) -> String {
    let htmlEntities: [String: String] = [
      "&amp;": "&",
      "&lt;": "<",
      "&gt;": ">",
      "&quot;": "\"",
      "&apos;": "'",
      "&nbsp;": " ",
      "&#39;": "'",
      "&#x27;": "'",
      "&rsquo;": "'",
      "&lsquo;": "'",
      "&rdquo;": "\"",
      "&ldquo;": "\"",
      "&mdash;": "—",
      "&ndash;": "–",
      "&hellip;": "…",
      "&bull;": "•",
      "&deg;": "°",
      "&copy;": "©",
      "&reg;": "®",
      "&trade;": "™",
      "&euro;": "€",
      "&pound;": "£",
      "&yen;": "¥",
      "&cent;": "¢",
      "&sect;": "§",
      "&para;": "¶",
      "&middot;": "·",
      "&frac12;": "½",
      "&frac14;": "¼",
      "&frac34;": "¾",
      "&sup1;": "¹",
      "&sup2;": "²",
      "&sup3;": "³",
      "&times;": "×",
      "&divide;": "÷",
      "&plusmn;": "±",
    ]

    var result = text

    // Replace named entities first
    for (entity, replacement) in htmlEntities {
      result = result.replacingOccurrences(of: entity, with: replacement, options: .caseInsensitive)
    }

    // Handle numeric entities manually since we can't use callback-style replacement
    result = decodeNumericEntities(result)

    return result
  }

  private static func decodeNumericEntities(_ text: String) -> String {
    var index = text.startIndex
    var output = ""

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
      while cursor < text.endIndex, text[cursor] != ";" {
        cursor = text.index(after: cursor)
      }

      guard cursor < text.endIndex else {
        output.append(contentsOf: text[index..<text.endIndex])
        return output
      }

      let entityRange = index...cursor
      let numberString = String(text[valueStart..<cursor])

      if numberString.isEmpty {
        output.append(contentsOf: text[entityRange])
        index = text.index(after: cursor)
        continue
      }

      let parsedValue: Int?
      if isHex {
        parsedValue = Int(numberString, radix: 16)
      } else {
        parsedValue = Int(numberString)
      }

      if let value = parsedValue, let scalar = UnicodeScalar(value) {
        output.unicodeScalars.append(scalar)
      } else {
        output.append(contentsOf: text[entityRange])
      }

      index = text.index(after: cursor)
    }

    return output
  }

  // MARK: - Text Parsing

  private static func parseTextParts(_ text: String) -> [TextPart] {
    var parts: [TextPart] = []
    var currentText = ""
    let formatStack = FormatStack()

    var index = text.startIndex

    while index < text.endIndex {
      if text[index] == "<" {
        // Save current text if any
        if !currentText.isEmpty {
          parts.append(TextPart(text: currentText, format: formatStack.current))
          currentText = ""
        }

        // Parse tag
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

    // Add remaining text
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
      // Decode HTML entities in the text content
      let decodedText = decodeHTMLEntities(part.text)

      var attributedPart = AttributedString(decodedText)
      var resolvedFont = baseFont

      if part.format.isBold {
        resolvedFont = resolvedFont.weight(.bold)
      }

      if part.format.isItalic {
        resolvedFont = resolvedFont.italic()
      }

      attributedPart.font = resolvedFont

      if let linkURL = part.format.linkURL {
        attributedPart.link = linkURL
      }

      if part.format.isUnderlined {
        attributedPart.underlineStyle = .single
      }

      if part.format.isStrikethrough {
        attributedPart.strikethroughStyle = .single
      }

      if part.format.isMarked {
        attributedPart.backgroundColor = Color.yellow.opacity(0.3)
      }

      if part.format.isItalic {
        attributedPart[AttributeScopes.UIKitAttributes.ObliquenessAttribute.self] = 0.2
      }

      result.append(attributedPart)
    }

    return result
  }

  // MARK: - Menu Rendering

  @ViewBuilder
  private func menuBody(_ config: MenuConfig) -> some View {
    let lines = parseMenuLines(config)
    VStack(alignment: .leading, spacing: 2) {
      ForEach(Array(lines.enumerated()), id: \.offset) { _, line in
        switch line {
        case .empty:
          Color.clear.frame(height: 12)
        case .plain(let html):
          HTMLText(html)
        case .mixed(let segments):
          FlowLayout {
            ForEach(Array(flowItems(from: segments).enumerated()), id: \.offset) { _, item in
              switch item {
              case .word(let attrStr):
                Text(attrStr)
              case .menu(let attrStr, let plainText):
                Menu {
                  config.content(plainText)
                } label: {
                  Text(attrStr)
                    .foregroundColor(.accentColor)
                }
              }
            }
          }
        }
      }
    }
  }

  private func parseMenuLines(_ config: MenuConfig) -> [MenuLine] {
    let preprocessed = Self.preprocessHTML(html)
    return
      preprocessed
      .split(separator: "\n", omittingEmptySubsequences: false)
      .map { substring in
        let lineStr = String(substring).trimmingCharacters(in: .whitespaces)
        if lineStr.isEmpty { return .empty }
        let segments = parseMenuSegments(lineStr, config: config)
        if segments.count == 1, case .text = segments[0] {
          return .plain(lineStr)
        }
        return .mixed(segments)
      }
  }

  private func parseMenuSegments(_ line: String, config: MenuConfig) -> [MenuSegment] {
    // Parse HTML to get text parts with formatting info
    let textParts = Self.parseTextParts(line)

    // Build decoded string and track format at each character position
    var decoded = ""
    var formatRanges: [(range: Range<Int>, format: TextFormat)] = []

    for part in textParts {
      let partDecoded = Self.decodeHTMLEntities(part.text)
      let startOffset = decoded.count
      decoded += partDecoded
      let endOffset = decoded.count
      if startOffset < endOffset {
        formatRanges.append((startOffset..<endOffset, part.format))
      }
    }

    // Find matches in decoded text
    let matches = decoded.matches(of: config.pattern)
    let validMatches = matches.filter { match in
      if let validator = config.validator {
        return validator(decoded, match.range.lowerBound)
      }
      return true
    }

    guard !validMatches.isEmpty else { return [.text(line)] }

    // Helper to find format at a given offset
    func formatAt(_ offset: Int) -> TextFormat {
      for (range, format) in formatRanges where range.contains(offset) {
        return format
      }
      return .plain
    }

    // Build segments, splitting text parts at match boundaries
    var segments: [MenuSegment] = []
    var currentOffset = 0

    for match in validMatches {
      let matchStart = decoded.distance(from: decoded.startIndex, to: match.range.lowerBound)
      let matchEnd = decoded.distance(from: decoded.startIndex, to: match.range.upperBound)
      let matchText = String(decoded[match.range])

      // Add text segment for content before this match
      if currentOffset < matchStart {
        let beforeStart = decoded.index(decoded.startIndex, offsetBy: currentOffset)
        let beforeEnd = decoded.index(decoded.startIndex, offsetBy: matchStart)
        let beforeText = String(decoded[beforeStart..<beforeEnd])
        segments.append(
          .text(rebuildHTML(beforeText, from: currentOffset, formatRanges: formatRanges))
        )
      }

      // Add match segment with its format
      let matchFormat = formatAt(matchStart)
      segments.append(.match(matchText, matchFormat))

      currentOffset = matchEnd
    }

    // Add remaining text after last match
    if currentOffset < decoded.count {
      let remainingStart = decoded.index(decoded.startIndex, offsetBy: currentOffset)
      let remainingText = String(decoded[remainingStart...])
      segments.append(
        .text(rebuildHTML(remainingText, from: currentOffset, formatRanges: formatRanges))
      )
    }

    return segments
  }

  // Rebuild HTML string for text between matches, preserving all format changes
  private func rebuildHTML(
    _ text: String,
    from startOffset: Int,
    formatRanges: [(range: Range<Int>, format: TextFormat)]
  ) -> String {
    guard !text.isEmpty else { return text }

    // Helper to find format at a given offset
    func formatAt(_ offset: Int) -> TextFormat {
      for (range, format) in formatRanges where range.contains(offset) {
        return format
      }
      return .plain
    }

    // Helper to wrap text with format tags
    func wrapWithTags(_ str: String, _ format: TextFormat) -> String {
      guard !str.isEmpty else { return str }
      var result = str

      if format.isBold {
        result = "<b>\(result)</b>"
      }
      if format.isItalic {
        result = "<i>\(result)</i>"
      }
      if format.isUnderlined {
        result = "<u>\(result)</u>"
      }
      if format.isStrikethrough {
        result = "<s>\(result)</s>"
      }
      if format.isMarked {
        result = "<mark>\(result)</mark>"
      }
      if let url = format.linkURL {
        result = "<a href=\"\(url.absoluteString)\">\(result)</a>"
      }

      return result
    }

    // Split text at format boundaries and wrap each piece
    var result = ""
    var currentChunk = ""
    var currentFormat = formatAt(startOffset)
    var offset = startOffset

    for char in text {
      let charFormat = formatAt(offset)

      if charFormat != currentFormat {
        // Format changed, wrap accumulated chunk and start new one
        result += wrapWithTags(currentChunk, currentFormat)
        currentChunk = String(char)
        currentFormat = charFormat
      } else {
        currentChunk.append(char)
      }

      offset += 1
    }

    // Wrap final chunk
    result += wrapWithTags(currentChunk, currentFormat)

    return result
  }

  private func flowItems(from segments: [MenuSegment]) -> [FlowItem] {
    let baseFont = environmentFont ?? .body
    var items: [FlowItem] = []

    for segment in segments {
      switch segment {
      case .text(let html):
        let textParts = Self.parseTextParts(html)

        for part in textParts {
          let decoded = Self.decodeHTMLEntities(part.text)
          var remaining = decoded[decoded.startIndex...]

          while !remaining.isEmpty {
            guard let firstNonSpace = remaining.firstIndex(where: { $0 != " " }) else {
              items.append(
                .word(buildFlowAttributedString(String(remaining), part.format, baseFont))
              )
              break
            }
            let wordStart = remaining.startIndex
            let afterWord = remaining[firstNonSpace...].firstIndex(of: " ") ?? remaining.endIndex
            var wordEnd = afterWord
            while wordEnd < remaining.endIndex && remaining[wordEnd] == " " {
              wordEnd = remaining.index(after: wordEnd)
            }
            let wordString = String(remaining[wordStart..<wordEnd])
            items.append(.word(buildFlowAttributedString(wordString, part.format, baseFont)))
            remaining = remaining[wordEnd...]
          }
        }

      case .match(let str, let format):
        let attrStr = buildFlowAttributedString(str, format, baseFont)
        items.append(.menu(attrStr, str))
      }
    }
    return items
  }

  private func buildFlowAttributedString(_ text: String, _ format: TextFormat, _ baseFont: Font)
    -> AttributedString
  {
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
      let lowercase = trimmed.lowercased()

      switch lowercase {
      case "<b>": self = .boldOpen
      case "</b>": self = .boldClose
      case "<strong>": self = .strongOpen
      case "</strong>": self = .strongClose
      case "<i>": self = .italicOpen
      case "</i>": self = .italicClose
      case "<em>": self = .emOpen
      case "</em>": self = .emClose
      case "<u>": self = .underlineOpen
      case "</u>": self = .underlineClose
      case "<strike>": self = .strikeOpen
      case "</strike>": self = .strikeClose
      case "<s>": self = .sOpen
      case "</s>": self = .sClose
      case "<del>": self = .delOpen
      case "</del>": self = .delClose
      case "<mark>": self = .markOpen
      case "</mark>": self = .markClose
      case "</a>": self = .anchorClose
      default:
        if lowercase.hasPrefix("<a") {
          let url = Self.extractHref(from: trimmed)
          self = .anchorOpen(url)
        } else {
          self = .unknown
        }
      }
    }

    private static func extractHref(from tagString: String) -> URL? {
      // Match href="..." or href='...'
      let patterns = [
        #"href\s*=\s*"([^"]+)""#,
        #"href\s*=\s*'([^']+)'"#,
      ]

      for pattern in patterns {
        if let regex = try? NSRegularExpression(
          pattern: pattern,
          options: [.caseInsensitive]
        ) {
          let nsRange = NSRange(tagString.startIndex..<tagString.endIndex, in: tagString)
          if let match = regex.firstMatch(in: tagString, options: [], range: nsRange),
            let hrefRange = Range(match.range(at: 1), in: tagString)
          {
            let urlString = String(tagString[hrefRange])
            return URL(string: urlString)
          }
        }
      }

      return nil
    }
  }

  private struct MenuConfig {
    let pattern: Regex<Substring>
    let validator: ((String, String.Index) -> Bool)?
    let content: (String) -> AnyView
  }

  private enum MenuLine {
    case empty
    case plain(String)
    case mixed([MenuSegment])
  }

  private enum MenuSegment {
    case text(String)
    case match(String, TextFormat)
  }

  private enum FlowItem {
    case word(AttributedString)
    case menu(AttributedString, String)
  }

  private struct FlowLayout: Layout {
    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
      arrange(in: proposal, subviews: subviews).size
    }

    func placeSubviews(
      in bounds: CGRect,
      proposal: ProposedViewSize,
      subviews: Subviews,
      cache: inout ()
    ) {
      let result = arrange(
        in: ProposedViewSize(width: bounds.width, height: bounds.height),
        subviews: subviews
      )
      for (index, position) in result.positions.enumerated() {
        subviews[index]
          .place(
            at: CGPoint(x: bounds.minX + position.x, y: bounds.minY + position.y),
            proposal: .unspecified
          )
      }
    }

    private func arrange(in proposal: ProposedViewSize, subviews: Subviews) -> (
      positions: [CGPoint], size: CGSize
    ) {
      var positions: [CGPoint] = []
      var x: CGFloat = 0
      var y: CGFloat = 0
      var rowHeight: CGFloat = 0
      let maxWidth = proposal.width ?? .infinity

      for subview in subviews {
        let size = subview.sizeThatFits(.unspecified)
        if x + size.width > maxWidth && x > 0 {
          x = 0
          y += rowHeight
          rowHeight = 0
        }
        positions.append(CGPoint(x: x, y: y))
        x += size.width
        rowHeight = max(rowHeight, size.height)
      }

      return (positions: positions, size: CGSize(width: maxWidth, height: y + rowHeight))
    }
  }

  // MARK: - Testing

  #if DEBUG
  public static func buildAttributedStringForTesting(html: String, font: Font = .body)
    -> AttributedString?
  {
    buildAttributedString(html: html, font: font)
  }
  #endif
}

// MARK: - Previews

#if DEBUG
#Preview("HTMLText Gallery") {
  HTMLTextPreviewGallery()
}

#Preview("Menu + HTML Formatting") {
  HTMLTextMenuPreview()
}
#endif
