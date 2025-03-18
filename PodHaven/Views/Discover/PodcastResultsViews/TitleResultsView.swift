// Copyright Justin Bishop, 2025

import SwiftUI

struct TitleResultsView: View {
  private let viewModel: TitleResultsViewModel

  init(viewModel: TitleResultsViewModel) {
    self.viewModel = viewModel
  }

  var body: some View {
    Text("Titles").font(.largeTitle).navigationTitle("Titles")
  }
}

// TODO: Make a preview

