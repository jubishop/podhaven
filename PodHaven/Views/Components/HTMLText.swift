// Copyright Justin Bishop, 2024

import SwiftUI

struct HTMLText: View {
  let html: String
  var color: Color
  var font: Font

  init(_ html: String, color: Color = .primary, font: Font = .body) {
    self.html = html
    self.color = color
    self.font = font
  }

  var body: some View {
    if html.isHTML(),
      let data = html.data(using: .utf8),
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
      Text(html).foregroundStyle(color).font(font)
    }
  }

  private func applyCustomStyles(
    to nsAttributedString: NSMutableAttributedString
  ) -> NSAttributedString {
    let fullRange = NSRange(location: 0, length: nsAttributedString.length)

    nsAttributedString.enumerateAttribute(
      .font,
      in: fullRange,
      options: []
    ) { (value, range, _) in
      if let originalFont = value as? UIFont {
        var newUIFont = uiFont(for: font)
        if let mergedDescriptor = newUIFont.fontDescriptor.withSymbolicTraits(
          originalFont.fontDescriptor.symbolicTraits
        ) {
          newUIFont = UIFont(
            descriptor: mergedDescriptor,
            size: newUIFont.pointSize
          )
        }
        nsAttributedString.addAttribute(
          .font,
          value: newUIFont,
          range: range
        )
      }
    }

    nsAttributedString.addAttribute(
      .foregroundColor,
      value: UIColor(color),
      range: fullRange
    )
    return nsAttributedString
  }

  private func uiFont(for font: Font) -> UIFont {
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

#Preview {
  HTMLText(
    """
    Lorem ipsum dolor sit amet, consectetur adipiscing elit. Nulla facilisi.
    <b>Quisque</b> <i>phasellus</i> <u>finibus</u> <strong>elementum</strong> <em>sollicitudin</em>.
    """,
    color: .blue,
    font: .largeTitle
  )
  .padding()
}
