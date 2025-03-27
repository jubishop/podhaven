// Copyright Justin Bishop, 2025

import SwiftUI

struct PersonResultsView: View {
  private let viewModel: PersonResultsViewModel

  init(viewModel: PersonResultsViewModel) {
    self.viewModel = viewModel
  }

  var body: some View {
    Text("People").font(.largeTitle).navigationTitle("People")
  }
}

// TODO: Make a preview
