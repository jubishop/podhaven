// Copyright Justin Bishop, 2025

import SwiftUI

struct SearchView: View {
  private let viewModel: DiscoverViewModel

  init(viewModel: DiscoverViewModel) {
    self.viewModel = viewModel
  }

  var body: some View {
    VStack {
      Image(systemName: "circle.dotted")
        .font(.largeTitle)  // Adjust size
        .foregroundColor(.blue)  // Adjust color
        .rotationEffect(.degrees(45))
      Text(viewModel.searchText)
      ForEach(viewModel.currentTokens) { currentToken in
        Text(currentToken.text)
      }
      Text("Is presented: \(viewModel.searchPresented)")
    }
  }
}

// TODO: Make a preview
