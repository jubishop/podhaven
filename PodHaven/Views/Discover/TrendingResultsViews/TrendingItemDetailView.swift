// Copyright Justin Bishop, 2025

import SwiftUI

struct TrendingItemDetailView: View {
  private let viewModel: TrendingItemDetailViewModel

  init(viewModel: TrendingItemDetailViewModel) {
    self.viewModel = viewModel
  }

  var body: some View {
    VStack(spacing: 40) {
      Text(viewModel.feedResult.title)
        .font(.largeTitle)
      Text(viewModel.feedResult.description)
    }
    .navigationTitle(viewModel.category)
  }
}

// TODO: Make preview
