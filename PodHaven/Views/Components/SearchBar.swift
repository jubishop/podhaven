// Copyright Justin Bishop, 2025

import SwiftUI

struct SearchBar: View {
  @FocusState private var isFocused: Bool

  private let fontSize = UIFont.preferredFont(forTextStyle: .body).pointSize

  @Binding var text: String
  var placeholder: String = "Search..."
  var imageName: String = AppLabel.search.systemImageName

  var body: some View {
    HStack {
      Image(systemName: imageName)

      TextField(placeholder, text: $text)
        .focused($isFocused)
        .textInputAutocapitalization(.never)
        .disableAutocorrection(true)

      if isFocused || !text.isEmpty {
        AppLabel.clearSearch.imageButton {
          text = ""
          isFocused = false
        }
      }
    }
  }
}

#if DEBUG
#Preview {
  @Previewable @State var text: String = ""
  @Previewable @State var demo: String = ""

  VStack(spacing: 20) {
    SearchBar(text: $text)
    TextField("Random focus field", text: $demo)
  }
}
#endif
