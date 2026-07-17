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
          .accessibilityHidden(true)

        TextField(prompt, text: $text)
          .focused($isFocused)
          .textInputAutocapitalization(.never)
          .disableAutocorrection(true)
      }
      .padding(12)
      .glassEffect(.regular)

      if isFocused || !text.isEmpty {
        AppIcon.clearSearch
          .imageButton {
            text = ""
            // Resign focus in a follow-up transaction: dropping focus in the
            // same action that clears the text collapses this button's `if`
            // wrapper while its own tap is still being handled, which can
            // swallow the focus change and leave the keyboard up.
            Task { @MainActor in isFocused = false }
          }
          .buttonStyle(.plain)
          .padding(16)
          .glassEffect(.regular.interactive(), in: .circle)
      }
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
