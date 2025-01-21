// Copyright Justin Bishop, 2025

import SwiftUI

struct TrendingItemDetailView: View {
  @Environment(Alert.self) var alert

  private let viewModel: TrendingItemDetailViewModel

  init(viewModel: TrendingItemDetailViewModel) {
    self.viewModel = viewModel
  }

  var body: some View {
    VStack(spacing: 40) {
      Text(viewModel.feedResult.title)
        .font(.largeTitle)
      HTMLText(viewModel.feedResult.description)
      if viewModel.unsavedEpisodes.isEmpty {
        Text("Loading episodes")
      } else {
        List(viewModel.unsavedEpisodes, id: \.guid) { unsavedEpisode in
          Text(unsavedEpisode.toString)
        }
      }
    }
    .navigationTitle(viewModel.category)
    .task {
      do {
        try await viewModel.fetchFeed()
      } catch {
        alert.andReport(error)
      }
    }
  }
}

#Preview {
  @Previewable @State var viewModel: TrendingItemDetailViewModel?

  NavigationStack {
    if let viewModel = viewModel {
      TrendingItemDetailView(viewModel: viewModel)
    }
  }
  .preview()
  .task {
    viewModel = TrendingItemDetailViewModel(
      category: "News",
      feedResult: try! await PreviewHelpers.loadFeedResult()
    )
  }
}
