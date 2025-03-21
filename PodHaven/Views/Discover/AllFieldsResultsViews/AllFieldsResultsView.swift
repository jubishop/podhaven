// Copyright Justin Bishop, 2025

import SwiftUI

struct AllFieldsResultsView: View {
  private let viewModel: AllFieldsResultsViewModel

  init(viewModel: AllFieldsResultsViewModel) {
    self.viewModel = viewModel
  }

  var body: some View {
    VStack {
      if viewModel.termResult != nil {
        List {
          ForEach(viewModel.unsavedPodcasts, id: \.feedURL) { unsavedPodcast in
            NavigationLink(
              value: SearchedPodcastByTerm(
                unsavedPodcast: unsavedPodcast,
                searchText: viewModel.searchText
              ),
              label: {
                Text("TODO")
              }
            )
          }
        }
        .navigationDestination(
          for: SearchedPodcastByTerm.self,
          destination: { termPodcast in
            Text("TODO")
          }
        )
      } else {
        Text("Still searching")
        Spacer()
      }
    }
    .navigationTitle("🔍📖 \(viewModel.searchText)")
  }
}

#Preview {
  @Previewable @State var viewModel: AllFieldsResultsViewModel?

  NavigationStack {
    if let viewModel = viewModel {
      AllFieldsResultsView(viewModel: viewModel)
    }
  }
  .preview()
  .task {
    viewModel = AllFieldsResultsViewModel(
      searchText: "Hard Fork",
      termResult: try! await PreviewHelpers.loadTermResult()
    )
  }
}
