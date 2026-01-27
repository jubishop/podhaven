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
          Color.clear.frame(height: 8)
        case .plain(let html):
          HTMLText(html)
        case .mixed(let segments):
          FlowLayout {
            ForEach(Array(flowItems(from: segments).enumerated()), id: \.offset) { _, item in
              switch item {
              case .word(let str):
                Text(str)
              case .menu(let str):
                Menu {
                  config.content(str)
                } label: {
                  Text(str)
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
    let stripped = line.replacingOccurrences(
      of: "<[^>]+>",
      with: "",
      options: .regularExpression
    )
    let decoded = Self.decodeHTMLEntities(stripped)

    let matches = decoded.matches(of: config.pattern)
    let validMatches = matches.filter { match in
      if let validator = config.validator {
        return validator(decoded, match.range.lowerBound)
      }
      return true
    }

    guard !validMatches.isEmpty else { return [.text(line)] }

    // Map decoded-string ranges back to find split points in the original HTML line.
    // We locate each matched text literally in the remaining HTML string.
    var segments: [MenuSegment] = []
    var remaining = line
    for match in validMatches {
      let matchText = String(decoded[match.range])
      if let range = remaining.range(of: matchText) {
        let before = String(remaining[remaining.startIndex..<range.lowerBound])
        if !before.isEmpty {
          segments.append(.text(before))
        }
        segments.append(.match(matchText))
        remaining = String(remaining[range.upperBound...])
      }
    }
    if !remaining.isEmpty {
      segments.append(.text(remaining))
    }

    return segments
  }

  private func flowItems(from segments: [MenuSegment]) -> [FlowItem] {
    var items: [FlowItem] = []
    for segment in segments {
      switch segment {
      case .text(let html):
        let stripped = html.replacingOccurrences(
          of: "<[^>]+>",
          with: "",
          options: .regularExpression
        )
        let decoded = Self.decodeHTMLEntities(stripped)
        // Split into words, each including its trailing whitespace
        var remaining = decoded[decoded.startIndex...]
        while !remaining.isEmpty {
          guard let firstNonSpace = remaining.firstIndex(where: { $0 != " " }) else {
            items.append(.word(String(remaining)))
            break
          }
          let wordStart = remaining.startIndex
          let afterWord = remaining[firstNonSpace...].firstIndex(of: " ") ?? remaining.endIndex
          var wordEnd = afterWord
          while wordEnd < remaining.endIndex && remaining[wordEnd] == " " {
            wordEnd = remaining.index(after: wordEnd)
          }
          items.append(.word(String(remaining[wordStart..<wordEnd])))
          remaining = remaining[wordEnd...]
        }
      case .match(let str):
        items.append(.menu(str))
      }
    }
    return items
  }

  // MARK: - Supporting Types

  private struct TextPart {
    let text: String
    let format: TextFormat
  }

  private struct TextFormat {
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
    case match(String)
  }

  private enum FlowItem {
    case word(String)
    case menu(String)
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
private struct HTMLTextPreviewList: View {
  struct Sample {
    let description: String
    let html: String
    let color: Color
    let font: Font
  }

  let title: String
  let samples: [Sample]

  var body: some View {
    ScrollView {
      VStack(alignment: .leading, spacing: 16) {
        Text(title)
          .font(.title2)
          .bold()

        ForEach(Array(samples.enumerated()), id: \.offset) { index, sample in
          VStack(alignment: .leading, spacing: 8) {
            Text(sample.description)
              .font(.headline)
            HTMLText(sample.html)
              .font(sample.font)
              .foregroundStyle(sample.color)
          }

          if index < samples.count - 1 {
            Divider()
          }
        }
      }
      .padding()
    }
  }
}

private struct HTMLTextPreviewGroup {
  let title: String
  let samples: [HTMLTextPreviewList.Sample]
}

private let htmlTextPreviewGroups: [HTMLTextPreviewGroup] = [
  .init(
    title: "Basic Styles",
    samples: [
      .init(
        description: "Bold, italic, and underline",
        html: "<b>Bold text</b>, <i>italic text</i>, and <u>underlined text</u>.",
        color: .primary,
        font: .body
      ),
      .init(
        description: "Strong and emphasis tags",
        html: "<strong>Strong text</strong> and <em>emphasized text</em> work too.",
        color: .secondary,
        font: .body
      ),
      .init(
        description: "Nested combinations",
        html:
          "You can combine <b><i>bold and italic</i></b>, or even <b><i><u>all three styles</u></i></b>!",
        color: .blue,
        font: .body
      ),
      .init(
        description: "Different font scales",
        html: "<b>Large Title:</b> This is <i>important</i> information!",
        color: .purple,
        font: .largeTitle
      ),
    ]
  ),
  .init(
    title: "Paragraphs & Line Breaks",
    samples: [
      .init(
        description: "Paragraph separation",
        html: "<p>First paragraph with some content.</p><p>Second paragraph after a break.</p>",
        color: .primary,
        font: .body
      ),
      .init(
        description: "Explicit line breaks",
        html: "Line one<br/>Line two<br />Line three<br>Line four",
        color: .orange,
        font: .body
      ),
      .init(
        description: "Truncated API response",
        html:
          "<h1>Episode Title That Got Cut Off</h1><p>This simulates how PodcastIndex API truncates descriptions mid-sentence without proper closing tags",
        color: .red,
        font: .body
      ),
    ]
  ),
  .init(
    title: "Entities & Symbols",
    samples: [
      .init(
        description: "Quotes and punctuation",
        html: "Quotation marks: &lsquo;single&rsquo; and &ldquo;double&rdquo; quotes work great!",
        color: .purple,
        font: .body
      ),
      .init(
        description: "Common entities",
        html:
          "Common entities: &amp; (ampersand), &lt; (less than), &gt; (greater than), &quot;quotes&quot;",
        color: .blue,
        font: .body
      ),
      .init(
        description: "Special characters",
        html: "Special chars: &mdash; em dash, &ndash; en dash, &hellip; ellipsis, &bull; bullet",
        color: .orange,
        font: .body
      ),
      .init(
        description: "Symbols and currency",
        html:
          "Symbols: &copy; &reg; &trade; &deg; &plusmn; &times; &divide; &euro;100 &pound;50 &yen;1000",
        color: .green,
        font: .body
      ),
    ]
  ),
  .init(
    title: "Links",
    samples: [
      .init(
        description: "Basic link",
        html: "Visit <a href=\"https://www.apple.com\">Apple's website</a> for more information.",
        color: .primary,
        font: .body
      ),
      .init(
        description: "Multiple links",
        html:
          "Check out <a href=\"https://github.com\">GitHub</a> and <a href=\"https://stackoverflow.com\">Stack Overflow</a> for coding help.",
        color: .blue,
        font: .body
      ),
      .init(
        description: "Formatted links",
        html:
          "<b>Links can have formatting:</b> <a href=\"https://www.swift.org\"><i>Swift.org</i></a> and <a href=\"https://developer.apple.com\"><b>Apple Developer</b></a>",
        color: .purple,
        font: .body
      ),
      .init(
        description: "Single quote href",
        html: #"Single quotes work too: <a href='https://www.example.com'>Example Site</a>"#,
        color: .green,
        font: .callout
      ),
    ]
  ),
  .init(
    title: "Complex & Edge Cases",
    samples: [
      .init(
        description: "Welcome message",
        html: """
          <p><b>Welcome to our app!</b></p>
          <p>Here you can find <i>amazing</i> content with <u>special</u> formatting.</p>
          <p>We support <b><i>multiple</i></b> styles and <br/><strong>proper paragraph spacing</strong>.</p>
          """,
        color: .indigo,
        font: .body
      ),
      .init(
        description: "Unclosed tags",
        html: "Edge case: <b>Unclosed bold and <i>nested italic</i> should still work properly.",
        color: .red,
        font: .caption
      ),
      .init(
        description: "Plain text fallback",
        html:
          "This text has no HTML tags, so it should display normally with the specified color and font.",
        color: .mint,
        font: .subheadline
      ),
      .init(
        description: "Truncated search snippet",
        html:
          "<p>Ever wondered how a podcast can truly reflect the soul of a city? Join us as we turn the tables on Erik Nilsson, the dynamic host who finds himself on the other side of the microphone...",
        color: .orange,
        font: .body
      ),
    ]
  ),
  .init(
    title: "Long-form Descriptions",
    samples: [
      .init(
        description: "Multi-paragraph episode synopsis",
        html: """
          <p><b>Episode 142: Mapping the Future</b> invites urban planner <i>Dr. Elena Cruz</i> to unpack how cities redesign transit for the AI era.</p>
          <p>We explore <u>dynamic zoning</u>, commuter twins, and why open data is the hidden catalyst for equitable streets. Discover the pilot projects rolling out in Austin, Seattle, and Berlin—and what it will take to scale them.</p>
          <p><a href=\"https://example.com/show-notes\">Read the full show notes</a> for maps, datasets, and a timeline of reforms.</p>
          """,
        color: .primary,
        font: .body
      ),
      .init(
        description: "Newsletter-style recap",
        html: """
          <p>Another week, another burst of podcast discovery: <strong>three new indie launches</strong>, an <em>audio drama revival</em>, and chart insights from across the globe.</p>
          <p>Tap through for the curated feed bundle, or jump straight to <a href=\"https://podhaven.app/curation\">our curators' picks</a>.</p>
          """,
        color: .secondary,
        font: .callout
      ),
    ]
  ),
  .init(
    title: "Malformed HTML Recovery",
    samples: [
      .init(
        description: "Missing closing tags",
        html:
          "<p><b>Live from the floor</b> our hosts recap the keynote with <i>breaking reactions",
        color: .pink,
        font: .body
      ),
      .init(
        description: "Double-encoded entities & stray brackets",
        html:
          "Latest update &amp;amp; quick hotfix &lt;br&gt; rolling out now &mdash; watch for &lt;unexpected&gt; surprises.",
        color: .orange,
        font: .footnote
      ),
    ]
  ),
  .init(
    title: "Release Notes & Bullet Lists",
    samples: [
      .init(
        description: "Changelog with bullets",
        html: """
          <p>&bull; Added <b>Smart Queue</b> reordering<br/>&bull; Improved offline caching stability<br/>&bull; Fixed &ldquo;Resume" button getting stuck</p>
          """,
        color: .teal,
        font: .body
      ),
      .init(
        description: "Feature spotlight",
        html: """
          <p>&bull; Spotlight: <em>Episode Sync</em> mirrors progress across devices.<br/>&bull; Coming soon: <u>Sleep Sync</u> with Apple Health.</p>
          """,
        color: .indigo,
        font: .callout
      ),
    ]
  ),
  .init(
    title: "Localization Stress",
    samples: [
      .init(
        description: "German longform",
        html:
          "<p><b>Neu:</b> Ein tiefes Gespräch über <i>Klimadaten</i> und offene Sensoren in europäischen Metropolen.</p>",
        color: .primary,
        font: .body
      ),
      .init(
        description: "French teaser",
        html:
          "<p>Suivez notre <em>série spéciale</em> sur les studios indépendants &mdash; interviews, coulisses et playlists.</p>",
        color: .purple,
        font: .body
      ),
      .init(
        description: "RTL snippet",
        html:
          "<p>اكتشف أحدث حلقاتنا عن <strong>التقنية</strong> و<span>الابتكار</span> حول العالم.</p>",
        color: .mint,
        font: .body
      ),
    ]
  ),
  .init(
    title: "Custom Fonts",
    samples: [
      .init(
        description: "Serif emphasis",
        html:
          "<p><b>Editor's Letter:</b> Discover the stories shaping podcasting this quarter.</p>",
        color: .primary,
        font: .system(size: 18, weight: .medium, design: .serif)
      ),
      .init(
        description: "Title casing",
        html: "<p><em>Spotlight:</em> Acoustic Design</p>",
        color: .brown,
        font: .title3
      ),
    ]
  ),
  .init(
    title: "Emoji & Multicodepoint",
    samples: [
      .init(
        description: "Emoji-rich teaser",
        html:
          "<p>🎙️ New episode drops tomorrow! 🚀 Dive into space tech with NASA's mission crew.</p>",
        color: .primary,
        font: .body
      ),
      .init(
        description: "Flags and sequences",
        html: "<p>Global round-up 🇺🇸 🇩🇪 🇯🇵 — plus bonus segments on music 🎧 and wellness 🧘‍♂️.</p>",
        color: .orange,
        font: .callout
      ),
      .init(
        description: "Entity + emoji mix",
        html: "<p>&#128640; &mdash; Counting down to launch with behind-the-scenes 📸.</p>",
        color: .blue,
        font: .body
      ),
    ]
  ),
  .init(
    title: "Font Variations",
    samples: [
      .init(
        description: "Default body",
        html: "<b>Body:</b> Inherits the environment body font size.",
        color: .primary,
        font: .body
      ),
      .init(
        description: "Semibold rounded",
        html: "<b>Rounded Semibold:</b> Emphasized text with a rounded design.",
        color: .mint,
        font: .system(size: 20, weight: .semibold, design: .rounded)
      ),
      .init(
        description: "Serif light",
        html: "<b>Serif Light:</b> Elegant typography for long-form reading.",
        color: .indigo,
        font: .system(size: 22, weight: .light, design: .serif)
      ),
      .init(
        description: "Monospaced heavy",
        html: "<b>Monospaced Heavy:</b> Great for highlighting code or identifiers.",
        color: .orange,
        font: .system(size: 18, weight: .heavy, design: .monospaced)
      ),
      .init(
        description: "Large title stylistic",
        html: "<b>Large Title:</b> This headline uses a palette-accented foreground.",
        color: .pink,
        font: .largeTitle
      ),
    ]
  ),
  .init(
    title: "Lists",
    samples: [
      .init(
        description: "Well-formed list",
        html: "<ul><li>First item</li><li>Second item</li><li>Third item</li></ul>",
        color: .primary,
        font: .body
      ),
      .init(
        description: "List with formatted content",
        html:
          "<ul><li><b>Bold item</b> with extra text</li><li>Item with <i>italic</i> styling</li><li>Item with a <a href=\"https://example.com\">link</a></li></ul>",
        color: .blue,
        font: .body
      ),
      .init(
        description: "Unclosed <li> tags (truncated feed)",
        html: "<ul><li>First item<li>Second item<li>Third item",
        color: .orange,
        font: .body
      ),
      .init(
        description: "Mixed closed and unclosed",
        html: "<ul><li>First item</li><li>Second item<li>Third item</li>",
        color: .purple,
        font: .body
      ),
      .init(
        description: "Orphan <li> without <ul>",
        html: "<p>Some text</p><li>Standalone item</li><li>Another item</li><p>More text</p>",
        color: .pink,
        font: .body
      ),
      .init(
        description: "List in context with paragraphs",
        html:
          "<p><b>What's New:</b></p><ul><li>Improved search algorithm</li><li>Better battery efficiency</li><li>New themes available</li></ul><p>Enjoy the update!</p>",
        color: .green,
        font: .callout
      ),
      .init(
        description: "List with HTML entities",
        html:
          "<ul><li>Support for &amp; symbols</li><li>Em dashes &mdash; work great</li><li>Quotes: &ldquo;double&rdquo; and &lsquo;single&rsquo;</li></ul>",
        color: .teal,
        font: .body
      ),
      .init(
        description: "Malformed: no closing tags at all",
        html: "<ul><li>Feature one<li>Feature two<li>Feature three",
        color: .red,
        font: .caption
      ),
      .init(
        description: "Empty list items",
        html: "<ul><li></li><li>Actual content</li><li></li></ul>",
        color: .secondary,
        font: .body
      ),
    ]
  ),
  .init(
    title: "Text Decorations",
    samples: [
      .init(
        description: "Simple strikethrough",
        html: "<s>Deprecated:</s> Old show notes link",
        color: .primary,
        font: .body
      ),
      .init(
        description: "Multiple strikes",
        html: "<strong>Updates:</strong> <del>Conference delayed</del> <s>Venue TBD</s>",
        color: .orange,
        font: .callout
      ),
      .init(
        description: "Highlighted snippet",
        html: "Remember to <mark>subscribe</mark> for bonus tips!",
        color: .primary,
        font: .body
      ),
      .init(
        description: "Dark theme check",
        html: "Night mode <mark>highlight</mark> with <s>strike</s> mix",
        color: .secondary,
        font: .body
      ),
    ]
  ),
]

private struct HTMLTextPreviewGallery: View {
  var body: some View {
    NavigationStack {
      List(htmlTextPreviewGroups, id: \.title) { group in
        NavigationLink(group.title) {
          HTMLTextPreviewList(title: group.title, samples: group.samples)
            .navigationTitle(group.title)
            .navigationBarTitleDisplayMode(.inline)
        }
      }
      .navigationTitle("HTMLText Scenarios")
    }
  }
}

#Preview {
  HTMLTextPreviewGallery()
}
#endif
