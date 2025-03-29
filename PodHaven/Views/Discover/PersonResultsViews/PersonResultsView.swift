// Copyright Justin Bishop, 2025

import SwiftUI

struct PersonResultsView: View {
  private let viewModel: PersonResultsViewModel

  init(viewModel: PersonResultsViewModel) {
    self.viewModel = viewModel
  }

  var body: some View {
    VStack {
      if viewModel.personResult != nil {
        PersonResultsListView(
          viewModel: PersonResultsListViewModel(searchResult: viewModel.searchResult)
        )
      } else {
        Text("Still searching")
        Spacer()
      }
    }
    .navigationTitle("🕵️ \(viewModel.searchText)")
  }
}

#Preview {
  @Previewable @State var viewModel: PersonResultsViewModel?

  NavigationStack {
    if let viewModel = viewModel {
      PersonResultsView(viewModel: viewModel)
    }
  }
  .preview()
  .task {
    let personResult = try! await PreviewHelpers.loadPersonResult()
    viewModel = PersonResultsViewModel(
      searchResult: PersonSearchResult(
        searchedText: "Neil deGrasse Tyson",
        personResult: personResult
      )
    )
  }
}
