import SwiftUI

struct TokenGridView<Token: Hashable, Content: View>: View {
  private let tokens: [Token]
  private let width: CGFloat
  private let horizontalSpacing: CGFloat
  private let verticalSpacing: CGFloat
  private let content: (Token) -> Content
  private var rows: [[Token]] = [[]]

  init(
    tokens: [Token],
    width: CGFloat,
    horizontalSpacing: CGFloat = 8,
    verticalSpacing: CGFloat = 8,
    @ViewBuilder content: @escaping (Token) -> Content
  ) {
    self.tokens = tokens
    self.width = width
    self.horizontalSpacing = horizontalSpacing
    self.verticalSpacing = verticalSpacing
    self.content = content

    var currentRowWidth: CGFloat = 0
    for token in tokens {
      let tokenWidth = measure(token).width
      if currentRowWidth + horizontalSpacing + tokenWidth > width {
        rows.append([token])
        currentRowWidth = tokenWidth
      } else {
        rows[rows.count - 1].append(token)
        currentRowWidth += horizontalSpacing + tokenWidth
      }
    }
  }

  var body: some View {
    VStack(alignment: .leading, spacing: verticalSpacing) {
      ForEach(rows, id: \.self) { row in
        HStack(spacing: horizontalSpacing) {
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

#if DEBUG
#Preview {
  @Previewable @State var width: CGFloat = 400
  @Previewable @State var horizontalSpacing: CGFloat = 4
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

  ScrollView {
    TokenGridView(
      tokens: tokens,
      width: width,
      horizontalSpacing: horizontalSpacing,
      verticalSpacing: verticalSpacing
    ) { token in
      Text(token)
        .font(.caption)
        .padding(4)
        .background(Color.blue.opacity(0.2))
        .foregroundColor(.blue)
        .cornerRadius(4)
    }
    .frame(width: width)
    .overlay(
      Rectangle()
        .stroke(Color.gray, lineWidth: 1)
    )
    .padding(.vertical)

    Divider()

    HStack {
      Text("Width: \(Int(width))")
      Slider(value: $width, in: 100...500, step: 1)
    }
    .padding(.horizontal)

    HStack {
      Text("Horizontal Spacing: \(Int(horizontalSpacing))")
      Slider(value: $horizontalSpacing, in: 1...100, step: 1)
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
#endif
