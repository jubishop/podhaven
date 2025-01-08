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
      let tokenWidth = measure(token).width
      if currentRowWidth + spacing + tokenWidth > width {
        rows.append([token])
        currentRowWidth = tokenWidth
      } else {
        rows[rows.count - 1].append(token)
        currentRowWidth += spacing + tokenWidth
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

  private func measure(_ token: Token) -> CGSize {
    UIHostingController(rootView: content(token)).view.intrinsicContentSize
  }
}

#Preview {
  @Previewable @State var gridWidth: CGFloat = 400
  @Previewable @State var spacing: CGFloat = 4
  @Previewable @State var verticalSpacing: CGFloat = 4

  let tokens: [String] = [
    "Swift", "UIKit", "Combine", "SwiftUI", "Foundation", "Xcode 16.0", "Objective-C++", "iOS",
    "macOS", "WatchKit", "ARKit", "RealityKit", "AppKit", "SceneKit", "CoreML", "CoreData",
    "Vision", "SpriteKit", "Metal", "Swift Package Manager", "Swift Playgrounds",
    "Interface Builder", "MVVM", "VIPER", "Clean Architecture", "Concurrency", "Swift Concurrency",
    "Async/Await", "Actor Model", "KeyPath", "Property Wrappers", "Generics",
    "Protocol Oriented Programming", "Extensions", "Closures", "Functional Programming",
    "State Management", "Environment", "View Modifiers", "Animations", "Gestures", "Auto Layout",
    "Stacks", "Grids", "Lists", "ForEach", "NavigationStack", "NavigationSplitView",
    "ObservableObject", "Published", "CombineSchedulers", "Swift Charts", "Reality Composer",
    "XCTest", "Test Driven Development", "Snapshot Testing", "Simulator", "Accessibility",
    "Localization", "Dark Mode", "Dynamic Type", "Core Animation", "Game Development", "SwiftLint",
    "Code Coverage", "Code Signing",
  ]

  VStack {
    TokenGridView(tokens: tokens, spacing: spacing, verticalSpacing: verticalSpacing) { token in
      Button(action: {
        print("Tapped on \(token)")
      }) {
        Text(token)
          .font(.caption)
          .padding(4)
          .background(Color.blue.opacity(0.2))
          .foregroundColor(.blue)
          .cornerRadius(4)
      }
    }
    .frame(width: gridWidth)
    .overlay(
      Rectangle()
        .stroke(Color.gray, lineWidth: 1)
    )
    .padding(.vertical)

    Divider()

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
