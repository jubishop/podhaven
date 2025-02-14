// Copyright Justin Bishop, 2025

import SwiftUI

struct SearchBar: View {
  @FocusState private var isFocused: Bool

  private let fontSize = UIFont.preferredFont(forTextStyle: .body).pointSize

  @Binding var text: String
  var placeholder: String = "Search..."
  var imageName: String = "magnifyingglass"

  var body: some View {
    HStack {
      Image(systemName: imageName)

      TextField(placeholder, text: $text)
        .focused($isFocused)
        .textInputAutocapitalization(.never)
        .disableAutocorrection(true)

      if isFocused {
        Button("Cancel") {
          text = ""
          isFocused = false
        }
      }
    }
    .padding(.horizontal)
  }
}

#Preview {
  @Previewable @State var text: String = ""

  SearchBar(text: $text)
}
