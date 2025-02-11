// Copyright Justin Bishop, 2025

import SwiftUI

struct SearchBar: View {
  @Binding var text: String

  var placeholder: String = "Search..."

  var body: some View {
    ZStack {
      let fontSize = UIFont.preferredFont(forTextStyle: .body).pointSize

      RoundedRectangle(cornerRadius: fontSize * 0.4)
        .fill(.thinMaterial)
        .frame(height: fontSize * 2)

      HStack {
        Image(systemName: "magnifyingglass")
          .foregroundColor(.gray)

        TextField(placeholder, text: $text)
          .textFieldStyle(.plain)
      }
      .padding(.horizontal)
    }
    .padding(.horizontal)
  }
}
