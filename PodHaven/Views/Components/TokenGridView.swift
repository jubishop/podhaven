// Copyright Justin Bishop, 2025 

import SwiftUI

struct TokenGridView: View {
  let tokens: [String] = [
    "Swift", "UIKit", "Combine", "SwiftUI", "Foundation",
    "Xcode", "Objective-C", "iOS", "macOS", "WatchKit", "ARKit", "RealityKit",
  ]

  var body: some View {
    FlowLayout(tokens: tokens) { token in
      Button(action: {
        print("Tapped on \(token)")
      }) {
        Text(token)
          .padding(.horizontal, 12)
          .padding(.vertical, 6)
          .background(Color.blue.opacity(0.2))
          .foregroundColor(.blue)
          .cornerRadius(8)
      }
    }
    .padding()
  }
}

struct FlowLayout<Content: View>: View {
  let tokens: [String]
  let content: (String) -> Content

  init(tokens: [String], @ViewBuilder content: @escaping (String) -> Content) {
    self.tokens = tokens
    self.content = content
  }

  var body: some View {
    GeometryReader { geometry in
      self.generateLayout(in: geometry.size.width)
    }
  }

  func generateLayout(in width: CGFloat) -> some View {
    var currentRowWidth: CGFloat = 0
    var rows: [[String]] = [[]]

    for token in tokens {
      let tokenWidth = token.size(withFont: .systemFont(ofSize: 16)) + 24
      if currentRowWidth + tokenWidth > width {
        rows.append([token])
        currentRowWidth = tokenWidth
      } else {
        rows[rows.count - 1].append(token)
        currentRowWidth += tokenWidth
      }
    }

    return VStack(alignment: .leading, spacing: 8) {
      ForEach(rows, id: \.self) { row in
        HStack(spacing: 8) {
          ForEach(row, id: \.self) { token in
            content(token)
          }
        }
      }
    }
  }
}

extension String {
  func size(withFont font: UIFont) -> CGFloat {
    let attributes = [NSAttributedString.Key.font: font]
    return (self as NSString).size(withAttributes: attributes).width
  }
}

#Preview {
    TokenGridView()
}
