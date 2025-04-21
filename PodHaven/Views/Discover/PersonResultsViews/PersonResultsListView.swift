// Copyright Justin Bishop, 2025

import Foundation
import SwiftUI

struct PersonResultsListView: View {
  @State private var viewModel: PersonResultsListViewModel

  init(viewModel: PersonResultsListViewModel) {
    self.viewModel = viewModel
  }

  var body: some View {
    VStack {
      HStack {
        SearchBar(
          text: $viewModel.episodeList.entryFilter,
          placeholder: "Filter episodes",
          imageName: "line.horizontal.3.decrease.circle"
        )

        Menu(
          content: {
            Button(viewModel.unplayedOnly ? "Show All" : "Unplayed Only") {
              viewModel.unplayedOnly.toggle()
            }
          },
          label: {
            Image(systemName: "line.horizontal.3.decrease.circle")
          }
        )
      }
      .padding(.horizontal)

      List(viewModel.episodeList.filteredEntries) { unsavedPodcastEpisode in
        NavigationLink(
          value: unsavedPodcastEpisode,
          label: {
            EpisodeListResultsView(
              viewModel: EpisodeListResultsViewModel(
                isSelected: $viewModel.episodeList.isSelected[unsavedPodcastEpisode],
                item: unsavedPodcastEpisode.unsavedEpisode,
                isSelecting: viewModel.episodeList.isSelecting
              )
            )
          }
        )
        .episodeSwipeActions(viewModel: viewModel, episode: unsavedPodcastEpisode)
      }
      .animation(.default, value: viewModel.episodeList.filteredEntries)
    }
    .navigationDestination(for: UnsavedPodcastEpisode.self) { unsavedPodcastEpisode in
      EpisodeResultsView(
        viewModel: EpisodeResultsViewModel(unsavedPodcastEpisode: unsavedPodcastEpisode)
      )
    }
    .toolbar {
      if viewModel.episodeList.isSelecting {
        ToolbarItem(placement: .topBarTrailing) {
          SelectableListMenu(list: viewModel.episodeList)
        }
      }

      if viewModel.episodeList.isSelecting, viewModel.episodeList.anySelected {
        ToolbarItem(placement: .topBarTrailing) {
          QueueableSelectableListMenu(list: viewModel)
        }
      }

      if viewModel.episodeList.isSelecting {
        ToolbarItem(placement: .topBarLeading) {
          Button("Done") {
            viewModel.episodeList.isSelecting = false
          }
        }
      } else {
        ToolbarItem(placement: .topBarTrailing) {
          Button("Select Episodes") {
            viewModel.episodeList.isSelecting = true
          }
        }
      }
    }
    .toolbarRole(.editor)
    .task { await viewModel.execute() }
  }
}

#if DEBUG
#Preview {
  @Previewable @State var viewModel: PersonResultsListViewModel?

  NavigationStack {
    if let viewModel = viewModel {
      PersonResultsListView(viewModel: viewModel)
    }
  }
  .preview()
  .task {
    let personResult = try! await PreviewHelpers.loadPersonResult()
    viewModel = PersonResultsListViewModel(
      searchResult: PersonSearchResult(
        searchText: "Neil deGrasse Tyson",
        personResult: personResult
      )
    )
  }
}
#endif
