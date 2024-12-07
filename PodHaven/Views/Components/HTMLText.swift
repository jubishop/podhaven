// Copyright Justin Bishop, 2024

import SwiftUI

struct HTMLText: View {
  let html: String
  var customColor: Color = .primary
  var font: Font = .body

  var body: some View {
    if let data = html.data(using: .utf8),
       let nsAttributedString = try? NSMutableAttributedString(
        data: data,
        options: [
          .documentType: NSAttributedString.DocumentType.html,
          .characterEncoding: String.Encoding.utf8.rawValue,
        ],
        documentAttributes: nil
      )
    {
      let modifiedAttributedString = applyCustomStyles(to: nsAttributedString)
      let attributedString = AttributedString(modifiedAttributedString)
      Text(attributedString)
    } else {
      Text(html).foregroundStyle(customColor).font(font)
    }
  }

  private func applyCustomStyles(to nsAttributedString: NSMutableAttributedString)
    -> NSAttributedString
  {
    nsAttributedString.enumerateAttributes(
      in: NSRange(location: 0, length: nsAttributedString.length)
    ) { attributes, range, _ in
      // Remove explicit color attributes
      if attributes.keys.contains(.foregroundColor) {
        nsAttributedString.removeAttribute(.foregroundColor, range: range)
      }

      // Apply custom font size based on SwiftUI Font
      if let fontSize = fontSize(for: font) {
        let currentFont =
          attributes[.font] as? UIFont
          ?? UIFont.systemFont(ofSize: UIFont.systemFontSize)
        let newFont = currentFont.withSize(fontSize)
        nsAttributedString.addAttribute(
          .font,
          value: newFont,
          range: range
        )
      }

      // Apply custom color
      nsAttributedString.addAttribute(
        .foregroundColor,
        value: UIColor(customColor),
        range: range
      )
    }

    return nsAttributedString
  }

  /// Maps SwiftUI Font styles to `CGFloat` font sizes.
  private func fontSize(for font: Font) -> CGFloat? {
    switch font {
    case .largeTitle:
      return UIFont.preferredFont(forTextStyle: .largeTitle).pointSize
    case .title:
      return UIFont.preferredFont(forTextStyle: .title1).pointSize
    case .title2:
      return UIFont.preferredFont(forTextStyle: .title2).pointSize
    case .title3:
      return UIFont.preferredFont(forTextStyle: .title3).pointSize
    case .headline:
      return UIFont.preferredFont(forTextStyle: .headline).pointSize
    case .subheadline:
      return UIFont.preferredFont(forTextStyle: .subheadline).pointSize
    case .body:
      return UIFont.preferredFont(forTextStyle: .body).pointSize
    case .callout:
      return UIFont.preferredFont(forTextStyle: .callout).pointSize
    case .caption:
      return UIFont.preferredFont(forTextStyle: .caption1).pointSize
    case .caption2:
      return UIFont.preferredFont(forTextStyle: .caption2).pointSize
    case .footnote:
      return UIFont.preferredFont(forTextStyle: .footnote).pointSize
    default:
      return nil
    }
  }
}

#Preview {
  HTMLText(
    html: """
      Lorem ipsum dolor sit amet, consectetur adipiscing elit. Nulla facilisi.
      <b>Quisque</b> <i>phasellus</i> <u>finibus</u> <strong>elementum</strong> <em>sollicitudin</em>.
      """,
    font: .largeTitle
  )
}
