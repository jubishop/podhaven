// Copyright Justin Bishop, 2025

import Factory
import SwiftUI

struct AllFieldsPodcastView: View {
  @State private var viewModel: PodcastResultsViewModel

  init(viewModel: PodcastResultsViewModel) {
    self.viewModel = viewModel
  }

  var body: some View {
    VStack {
      HTMLText(viewModel.unsavedPodcast.description)
        .lineLimit(3)
        .padding(.horizontal)

      if viewModel.subscribable {
        Button("Subscribe") {
          viewModel.subscribe()
        }
      }

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

      if viewModel.unsavedEpisodes.isEmpty {
        Text("Loading episodes")
      } else {
        List(viewModel.episodeList.filteredEntries, id: \.guid) { unsavedEpisode in
          NavigationLink(
            value: UnsavedPodcastEpisode(
              unsavedPodcast: viewModel.unsavedPodcast,
              unsavedEpisode: unsavedEpisode
            ),
            label: {
              AllFieldsEpisodeListView(
                viewModel: EpisodeListResultsViewModel(
                  isSelected: $viewModel.episodeList.isSelected[unsavedEpisode],
                  item: unsavedEpisode,
                  isSelecting: viewModel.isSelecting
                )
              )
            }
          )
          .episodeSwipeActions(viewModel: viewModel, episode: unsavedEpisode)
        }
        .animation(.default, value: viewModel.episodeList.filteredEntries)
      }
    }
    .navigationTitle(viewModel.unsavedPodcast.title)
    .navigationDestination(
      for: UnsavedPodcastEpisode.self,
      destination: { unsavedPodcastEpisode in
        AllFieldsEpisodeView(
          viewModel: EpisodeResultsViewModel(
            unsavedPodcastEpisode: unsavedPodcastEpisode
          )
        )
      }
    )
    .toolbar {
      if viewModel.isSelecting {
        ToolbarItem(placement: .topBarTrailing) {
          SelectableListMenu(list: viewModel.episodeList)
        }
      }

      if viewModel.isSelecting, viewModel.episodeList.anySelected {
        ToolbarItem(placement: .topBarTrailing) {
          QueueableSelectableListMenu(list: viewModel)
        }
      }

      if viewModel.isSelecting {
        ToolbarItem(placement: .topBarLeading) {
          Button("Done") {
            viewModel.isSelecting = false
          }
        }
      } else {
        ToolbarItem(placement: .topBarTrailing) {
          Button("Select Episodes") {
            viewModel.isSelecting = true
          }
        }
      }
    }
    .toolbarRole(.editor)
    .task { await viewModel.execute() }
  }
}

#Preview {
  @Previewable @State var viewModel: PodcastResultsViewModel?
  @ObservationIgnored @LazyInjected(\.repo) var repo

  NavigationStack {
    if let viewModel = viewModel {
      AllFieldsPodcastView(viewModel: viewModel)
    }
  }
  .preview()
  .task {
    let unsavedPodcast = try! await PreviewHelpers.loadUnsavedPodcast()
    if let existingPodcastSeries = try? await repo.podcastSeries(unsavedPodcast.feedURL) {
      try! await repo.delete(existingPodcastSeries.id)
    }
    viewModel = PodcastResultsViewModel(
      context: SearchedPodcastByTerm(
        searchText: "News",
        unsavedPodcast: unsavedPodcast
      )
    )
  }
}
