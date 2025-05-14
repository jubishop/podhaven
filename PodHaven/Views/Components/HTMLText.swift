// Copyright Justin Bishop, 2025

import SwiftUI

struct HTMLText: View {
  @State private var attributedString: AttributedString?

  private let html: String
  private var color: Color
  private var font: Font

  init(_ html: String, color: Color = .primary, font: Font = .body) {
    self.html = html
    self.color = color
    self.font = font
  }

  var body: some View {
    Group {
      if let attributedString = attributedString {
        Text(attributedString)
      } else {
        Text(html)
          .foregroundStyle(color)
          .font(font)
      }
    }
    .onAppear {
      // This must be done in `onAppear` to avoid AttributeGraph cycles...
      buildAttributedString()
    }
  }

  private func buildAttributedString() {
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
      print("making html out of \(html)")
      let modifiedAttributedString = applyCustomStyles(to: nsAttributedString)
      self.attributedString = AttributedString(modifiedAttributedString)
    } else {
      print("not html: \(html)")
    }
  }

  // MARK: - Private Helpers

  private func applyCustomStyles(
    to nsAttributedString: NSMutableAttributedString
  ) -> NSAttributedString {
    let fullRange = NSRange(location: 0, length: nsAttributedString.length)

    nsAttributedString.addAttribute(
      .foregroundColor,
      value: UIColor(color),
      range: fullRange
    )

    nsAttributedString.enumerateAttribute(
      .font,
      in: fullRange,
      options: []
    ) { (value, range, _) in
      if let originalFont = value as? UIFont {
        var newUIFont = HTMLText.uiFont(for: font)
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

    return nsAttributedString
  }

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
  VStack {
    HTMLText(
      """
      Lorem ipsum dolor sit amet, <p>consectetur adipiscing elit.</p> Nulla facilisi.
      <b>Quisque</b> <i>phasellus</i> <u>finibus</u> <strong>elementum</strong> <em>sollicitudin</em>.
      """,
      color: .blue,
      font: .largeTitle
    )
    .padding()

    HTMLText(
      """
      Lorem ipsum dolor sit amet, consectetur adipiscing elit. Nulla facilisi.
      """,
      color: .red,
      font: .footnote
    )
    .padding()

    HTMLText(
      """
      <p>Lorem ipsum dolor sit amet, consectetur adipiscing elit. Nulla facilisi.</p>
      """,
      color: .blue,
      font: .title
    )
    .padding()
  }
}
#endif
