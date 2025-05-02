// Copyright Justin Bishop, 2025

import Factory
import SwiftUI

struct StandardPodcastsView: View {
  @Environment(Alert.self) var alert

  @State private var viewModel: StandardPodcastsViewModel

  init(viewModel: StandardPodcastsViewModel) {
    self.viewModel = viewModel
  }

  var body: some View {
    HStack {
      SearchBar(
        text: $viewModel.podcastList.entryFilter,
        placeholder: "Filter podcasts",
        imageName: "line.horizontal.3.decrease.circle"
      )

      Menu(
        content: {
          ForEach(StandardPodcastsViewModel.SortMethod.allCases, id: \.self) { method in
            Button(method.rawValue) {
              viewModel.currentSortMethod = method
            }
            .disabled(viewModel.currentSortMethod == method)
          }
        },
        label: {
          Text("Sort by")
        }
      )
    }
    .padding(.horizontal)

    ScrollView {
      ItemGrid(items: viewModel.podcastList.filteredSortedEntries) {
        podcastWithLatestEpisodeDates in
        NavigationLink(
          value: podcastWithLatestEpisodeDates.podcast,
          label: {
            SelectablePodcastGridItem(
              viewModel: SelectablePodcastGridItemViewModel(
                isSelected: $viewModel.podcastList.isSelected[podcastWithLatestEpisodeDates],
                item: podcastWithLatestEpisodeDates.podcast,
                isSelecting: viewModel.isSelecting
              )
            )
          }
        )
      }
      .padding()
    }
    .navigationTitle(viewModel.title)
    .navigationDestination(for: Podcast.self) { podcast in
      PodcastView(viewModel: PodcastViewModel(podcast: podcast))
    }
    .refreshable {
      do {
        try await viewModel.refreshPodcasts()
      } catch {
        alert("Failed to refresh all podcasts: \(error)")
      }
    }
    .toolbar {
      if viewModel.isSelecting {
        ToolbarItem(placement: .topBarTrailing) {
          SelectableListMenu(list: viewModel.podcastList)
        }
      }

      if viewModel.isSelecting, viewModel.podcastList.anySelected {
        ToolbarItem(placement: .topBarTrailing) {
          Menu(
            content: {
              Button("Delete") {
                viewModel.deleteSelectedPodcasts()
              }
              if viewModel.anySelectedUnsubscribed {
                Button("Subscribe") {
                  viewModel.subscribeSelectedPodcasts()
                }
              }
              if viewModel.anySelectedSubscribed {
                Button("Unsubscribe") {
                  viewModel.unsubscribeSelectedPodcasts()
                }
              }
            },
            label: {
              Image(systemName: "ellipsis.circle")
            }
          )
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
          Button("Select Podcasts") {
            viewModel.isSelecting = true
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
  NavigationStack {
    StandardPodcastsView(viewModel: StandardPodcastsViewModel(title: "Preview Podcasts"))
  }
  .preview()
  .task {
    try! await PreviewHelpers.importPodcasts()
  }
}
#endif
