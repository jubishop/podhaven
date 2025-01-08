import SwiftUI

struct TokenGridView<Token: Hashable, Content: View>: View {
  let tokens: [Token]
  let content: (Token) -> Content

  init(tokens: [Token], @ViewBuilder content: @escaping (Token) -> Content) {
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
    var rows: [[Token]] = [[]]  // Array to hold rows of tokens

    // Measure and group tokens into rows
    for token in tokens {
      let tokenSize = measureToken(token: token).width
      if currentRowWidth + tokenSize + 8 > width {  // Check if token fits in current row
        rows.append([token])  // Create a new row
        currentRowWidth = tokenSize  // Reset row width
      } else {
        rows[rows.count - 1].append(token)  // Add to the current row
        currentRowWidth += tokenSize + 8  // Increment current row width (+ spacing)
      }
    }

    // Build the layout with calculated rows
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

  // Helper function to measure the size of a token's content
  func measureToken(token: Token) -> CGSize {
    let hostingView = UIHostingController(rootView: content(token))
    return hostingView.view.intrinsicContentSize
  }
}

#Preview {
  let tokens: [String] = [
    "Swift", "UIKit", "Combine", "SwiftUI", "Foundation",
    "Xcode 16.0", "Objective-C++", "iOS", "macOS", "WatchKit", "ARKit", "RealityKit",
  ]

  TokenGridView(tokens: tokens) { token in
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
  .preview()
}
