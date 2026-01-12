// Copyright Justin Bishop, 2025

import SwiftUI

struct SearchBar: View {
  @FocusState private var isFocused: Bool

  private let fontSize = UIFont.preferredFont(forTextStyle: .body).pointSize

  @Binding var text: String
  var prompt: String
  var searchIcon: AppIcon

  var body: some View {
    HStack {
      HStack {
        searchIcon.image

        TextField(prompt, text: $text)
          .focused($isFocused)
          .textInputAutocapitalization(.never)
          .disableAutocorrection(true)
      }
      .padding(12)
      .glassEffect(.regular)

      if showClearSearchButton {
        AppIcon.clearSearch
          .imageButton {
            text = ""
            isFocused = false
          }
          .buttonStyle(.plain)
          .padding(16)
          .glassEffect(.regular.interactive(), in: .circle)
          .transition(.scale.combined(with: .opacity))
      }
    }
    .animation(.easeInOut(duration: 0.15), value: showClearSearchButton)
  }

  private var showClearSearchButton: Bool {
    isFocused || !text.isEmpty
  }
}

#if DEBUG
#Preview {
  @Previewable @State var text: String = ""
  @Previewable @State var demo: String = ""

  VStack(spacing: 24) {
    SearchBar(text: $text, prompt: "Search", searchIcon: AppIcon.search)
    TextField("Random focus field", text: $demo)
  }
}
#endif
