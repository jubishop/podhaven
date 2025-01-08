import SwiftUI

struct TokenGridView<Token: Hashable, Content: View>: View {
  let tokens: [Token]
  let spacing: CGFloat
  let verticalSpacing: CGFloat
  let content: (Token) -> Content

  init(
    tokens: [Token],
    spacing: CGFloat = 8,
    verticalSpacing: CGFloat? = nil,
    @ViewBuilder content: @escaping (Token) -> Content
  ) {
    self.tokens = tokens
    self.spacing = spacing
    self.verticalSpacing = verticalSpacing ?? spacing
    self.content = content
  }

  var body: some View {
    GeometryReader { geometry in
      self.generateLayout(in: geometry.size.width)
    }
  }

  private func generateLayout(in width: CGFloat) -> some View {
    var currentRowWidth: CGFloat = 0
    var rows: [[Token]] = [[]]

    for token in tokens {
      let tokenSize = measureToken(token: token).width
      if currentRowWidth + tokenSize + spacing > width {
        rows.append([token])
        currentRowWidth = tokenSize
      } else {
        rows[rows.count - 1].append(token)
        currentRowWidth += tokenSize + spacing
      }
    }

    return VStack(alignment: .leading, spacing: verticalSpacing) {
      ForEach(rows, id: \.self) { row in
        HStack(spacing: spacing) {
          ForEach(row, id: \.self) { token in
            content(token)
          }
        }
      }
    }
  }

  private func measureToken(token: Token) -> CGSize {
    UIHostingController(rootView: content(token)).view.intrinsicContentSize
  }
}

#Preview {
  @Previewable @State var gridWidth: CGFloat = 300
  @Previewable @State var spacing: CGFloat = 8
  @Previewable @State var verticalSpacing: CGFloat = 8

  let tokens: [String] = [
    "Swift", "UIKit", "Combine", "SwiftUI", "Foundation", "Xcode 16.0", "Objective-C++", "iOS",
    "macOS", "WatchKit", "ARKit", "RealityKit",
  ]

  VStack {
    TokenGridView(tokens: tokens, spacing: spacing, verticalSpacing: verticalSpacing) { token in
      Button(action: {
        print("Tapped on \(token)")
      }) {
        Text(token)
          .padding(8)
          .background(Color.blue.opacity(0.2))
          .foregroundColor(.blue)
          .cornerRadius(8)
      }
    }
    .frame(width: gridWidth)  // Dynamically set the frame size
    .overlay(
      Rectangle()  // Or Rectangle if you prefer
        .stroke(Color.gray, lineWidth: 2)  // Set the color and width of the line
    )
    .padding(.vertical)

    HStack {
      Text("Width: \(Int(gridWidth))")
      Slider(value: $gridWidth, in: 100...500, step: 1)
    }
    .padding(.horizontal)

    HStack {
      Text("Spacing: \(Int(spacing))")
      Slider(value: $spacing, in: 1...100, step: 1)
    }
    .padding(.horizontal)

    HStack {
      Text("Vertical Spacing: \(Int(verticalSpacing))")
      Slider(value: $verticalSpacing, in: 1...100, step: 1)
    }
    .padding(.horizontal)
  }
  .padding()
  .preview()
}
