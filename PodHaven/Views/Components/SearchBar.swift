// Copyright Justin Bishop, 2025

import SwiftUI

struct SearchBar: View {
  @FocusState private var isFocused: Bool

  private let fontSize = UIFont.preferredFont(forTextStyle: .body).pointSize

  @Binding var text: String
  var placeholder: String = "Search..."
  var searchIcon: AppIcon

  var body: some View {
    HStack {
      HStack {
        searchIcon.image

        TextField(placeholder, text: $text)
          .focused($isFocused)
          .textInputAutocapitalization(.never)
          .disableAutocorrection(true)
      }
      .padding(10)
      .glassEffect(.regular)

      if isFocused || !text.isEmpty {
        AppIcon.clearSearch
          .imageButton {
            text = ""
            isFocused = false
          }
          .buttonStyle(.plain)
          .padding(12)
          .glassEffect(.regular.interactive(), in: .circle)
      }
    }
  }
}

#if DEBUG
#Preview {
  @Previewable @State var text: String = ""
  @Previewable @State var demo: String = ""

  VStack(spacing: 20) {
    SearchBar(text: $text, searchIcon: AppIcon.search)
    TextField("Random focus field", text: $demo)
  }
}
#endif
