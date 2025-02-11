// Copyright Justin Bishop, 2025

import SwiftUI

struct SearchBar: View {
  @FocusState private var isFocused: Bool

  private let fontSize = UIFont.preferredFont(forTextStyle: .body).pointSize

  @Binding var text: String
  var placeholder: String = "Search..."

  var body: some View {
    HStack {
      ZStack {
        RoundedRectangle(cornerRadius: fontSize * 0.4)
          .fill(.thinMaterial)
          .frame(height: fontSize * 2)

        HStack {
          Image(systemName: "magnifyingglass")
            .foregroundColor(.gray)

          TextField(placeholder, text: $text)
            .textFieldStyle(.plain)
            .focused($isFocused)
        }
        .padding(.horizontal)
      }

      if isFocused {
        Button(
          action: {
            text = ""
            isFocused = false
          },
          label: {
            Text("Cancel")
          }
        )
      }
    }
    .padding(.horizontal)
  }
}

#Preview {
  @Previewable @State var text: String = ""

  SearchBar(text: $text)
}
