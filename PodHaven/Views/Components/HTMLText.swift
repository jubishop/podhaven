// Copyright Justin Bishop, 2025

import SwiftUI

struct HTMLText: View {
  private let html: String
  private let color: Color
  private let font: Font

  init(_ html: String, color: Color = .primary, font: Font = .body) {
    self.html = html
    self.color = color
    self.font = font
  }

  var body: some View {
    if let attributedString = buildAttributedString() {
      Text(attributedString)
    } else {
      Text(html)
        .foregroundStyle(color)
        .font(font)
    }
  }

  // MARK: - Main Parsing

  private func buildAttributedString() -> AttributedString? {
    guard html.isHTML() else { return nil }

    let cleanedHTML = preprocessHTML(html)
    let textParts = parseTextParts(cleanedHTML)

    return buildAttributedString(from: textParts)
  }

  // MARK: - HTML Preprocessing

  private func preprocessHTML(_ htmlString: String) -> String {
    var result = htmlString

    // Handle paragraph tags with intelligent spacing
    result = handleParagraphTags(result)

    // Handle line breaks
    result = handleLineBreaks(result)

    // Clean up whitespace
    result = cleanupWhitespace(result)

    return result
  }

  private func handleParagraphTags(_ text: String) -> String {
    var result = text

    // Replace closing paragraphs with newlines
    result = result.replacingOccurrences(of: "</p>", with: "\n", options: .caseInsensitive)

    // Handle opening paragraphs - add newline unless at start
    if result.range(of: "^\\s*<p>", options: [.regularExpression, .caseInsensitive]) != nil {
      // Remove leading <p> tag
      result = result.replacingOccurrences(
        of: "^\\s*<p>",
        with: "",
        options: [.regularExpression, .caseInsensitive]
      )
    }

    // Replace remaining <p> tags with newlines
    result = result.replacingOccurrences(of: "<p>", with: "\n", options: .caseInsensitive)

    return result
  }

  private func handleLineBreaks(_ text: String) -> String {
    text.replacingOccurrences(
      of: "<br\\s*/?\\s*>",
      with: "\n",
      options: [.regularExpression, .caseInsensitive]
    )
  }

  private func cleanupWhitespace(_ text: String) -> String {
    text
      .replacingOccurrences(of: "\n{3,}", with: "\n\n", options: .regularExpression)
      .trimmingCharacters(in: .whitespacesAndNewlines)
  }

  // MARK: - Text Parsing

  private func parseTextParts(_ text: String) -> [TextPart] {
    var parts: [TextPart] = []
    var currentText = ""
    var formatStack = FormatStack()

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

  private func parseTag(from text: String, startingAt index: String.Index) -> (
    String.Index, HTMLTag
  )? {
    guard let tagEnd = text[index...].firstIndex(of: ">") else { return nil }

    let tagString = String(text[index...tagEnd]).lowercased()
    let tag = HTMLTag(rawValue: tagString)

    return (tagEnd, tag)
  }

  // MARK: - AttributedString Building

  private func buildAttributedString(from parts: [TextPart]) -> AttributedString {
    var result = AttributedString()
    let baseFont = Self.uiFont(for: font)

    for part in parts where !part.text.isEmpty {

      var attributedPart = AttributedString(part.text)
      attributedPart.foregroundColor = color
      attributedPart.font = Font(fontWithTraits(baseFont, traits: part.format.traits))

      if part.format.isUnderlined {
        attributedPart.underlineStyle = .single
      }

      result.append(attributedPart)
    }

    return result
  }

  private func fontWithTraits(_ baseFont: UIFont, traits: UIFontDescriptor.SymbolicTraits) -> UIFont
  {
    guard !traits.isEmpty else { return baseFont }

    let descriptor = baseFont.fontDescriptor.withSymbolicTraits(traits) ?? baseFont.fontDescriptor
    return UIFont(descriptor: descriptor, size: baseFont.pointSize)
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

    var traits: UIFontDescriptor.SymbolicTraits {
      var traits: UIFontDescriptor.SymbolicTraits = []
      if isBold { traits.insert(.traitBold) }
      if isItalic { traits.insert(.traitItalic) }
      return traits
    }

    static let plain = TextFormat(isBold: false, isItalic: false, isUnderlined: false)
  }

  private struct FormatStack {
    private var boldCount = 0
    private var italicCount = 0
    private var underlineCount = 0

    var current: TextFormat {
      TextFormat(
        isBold: boldCount > 0,
        isItalic: italicCount > 0,
        isUnderlined: underlineCount > 0
      )
    }

    mutating func processTag(_ tag: HTMLTag) {
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
    case unknown

    init(rawValue: String) {
      switch rawValue {
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
      default: self = .unknown
      }
    }
  }

  // MARK: - Font Mapping

  private static func uiFont(for font: Font) -> UIFont {
    let textStyleMapping: [Font: UIFont.TextStyle] = [
      .largeTitle: .largeTitle,
      .title: .title1,
      .title2: .title2,
      .title3: .title3,
      .headline: .headline,
      .subheadline: .subheadline,
      .body: .body,
      .callout: .callout,
      .caption: .caption1,
      .caption2: .caption2,
      .footnote: .footnote,
    ]
    let textStyle = textStyleMapping[font, default: .body]
    return UIFont.preferredFont(forTextStyle: textStyle)
  }
}

#if DEBUG
#Preview {
  ScrollView {
    VStack(alignment: .leading, spacing: 20) {
      Group {
        Text("Basic Formatting").font(.headline)

        HTMLText(
          "<b>Bold text</b>, <i>italic text</i>, and <u>underlined text</u>.",
          color: .primary,
          font: .body
        )

        HTMLText(
          "<strong>Strong text</strong> and <em>emphasized text</em> work too.",
          color: .secondary,
          font: .body
        )
      }

      Group {
        Text("Combined Formatting").font(.headline)

        HTMLText(
          "You can combine <b><i>bold and italic</i></b>, or even <b><i><u>all three styles</u></i></b>!",
          color: .blue,
          font: .body
        )

        HTMLText(
          "<b>Bold <i>with nested italic</i> back to bold</b> and normal.",
          color: .green,
          font: .callout
        )
      }

      Group {
        Text("Paragraphs and Line Breaks").font(.headline)

        HTMLText(
          "<p>First paragraph with some content.</p><p>Second paragraph after a break.</p>",
          color: .primary,
          font: .body
        )

        HTMLText(
          "Line one<br/>Line two<br />Line three<br>Line four",
          color: .orange,
          font: .body
        )
      }

      Group {
        Text("Different Font Sizes").font(.headline)

        HTMLText(
          "<b>Large Title:</b> This is <i>important</i> information!",
          color: .purple,
          font: .largeTitle
        )

        HTMLText(
          "<u>Small footnote</u> with <b>bold emphasis</b>.",
          color: .gray,
          font: .footnote
        )
      }

      Group {
        Text("Complex Examples").font(.headline)

        HTMLText(
          """
          <p><b>Welcome to our app!</b></p>
          <p>Here you can find <i>amazing</i> content with <u>special</u> formatting.</p>
          <p>We support <b><i>multiple</i></b> styles and <br/><strong>proper paragraph spacing</strong>.</p>
          """,
          color: .indigo,
          font: .body
        )

        HTMLText(
          "Edge case: <b>Unclosed bold and <i>nested italic</i> should still work properly.",
          color: .red,
          font: .caption
        )
      }

      Group {
        Text("Plain Text Fallback").font(.headline)

        HTMLText(
          "This text has no HTML tags, so it should display normally with the specified color and font.",
          color: .mint,
          font: .subheadline
        )
      }
    }
    .padding()
  }
}
#endif
