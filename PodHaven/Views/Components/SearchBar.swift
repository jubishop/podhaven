// Copyright Justin Bishop, 2025

import SwiftUI

struct SearchBar: View {
  @FocusState private var isFocused: Bool
  @State private var showClear = false

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

      if showClear {
        AppIcon.clearSearch
          .imageButton {
            text = ""
            isFocused = false
          }
          .buttonStyle(.plain)
          .padding(16)
          .glassEffect(.regular.interactive(), in: .circle)
          .transition(.move(edge: .trailing).combined(with: .opacity))
      }
    }
    .onChange(of: isFocused) { syncClearButton() }
    .onChange(of: text) { syncClearButton() }
    .onAppear { showClear = isFocused || !text.isEmpty }
  }

  // Drive visibility through explicit state inside withAnimation so focus-triggered
  // changes animate too: a plain computed condition with .animation(value:) animates
  // on text edits but not on focus changes, which made the clear button pop in
  // without sliding.
  private func syncClearButton() {
    withAnimation(.easeInOut(duration: 0.15)) {
      showClear = isFocused || !text.isEmpty
    }
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
