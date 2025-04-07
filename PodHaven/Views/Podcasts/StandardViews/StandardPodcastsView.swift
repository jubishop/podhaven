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
    SearchBar(
      text: $viewModel.podcastList.entryFilter,
      placeholder: "Filter podcasts",
      imageName: "line.horizontal.3.decrease.circle"
    )

    ScrollView {
      PodcastGrid(podcasts: viewModel.podcastList.filteredEntries.elements) { podcast in
        NavigationLink(
          value: podcast,
          label: {
            SelectablePodcastGridItem(
              viewModel: SelectablePodcastGridItemViewModel(
                isSelected: $viewModel.podcastList.isSelected[podcast],
                item: podcast,
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
        alert.andReport("Failed to refresh all podcasts: \(error)")
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

#Preview {
  NavigationStack {
    StandardPodcastsView(viewModel: StandardPodcastsViewModel(title: "Preview Podcasts"))
  }
  .preview()
  .task {
    try! await PreviewHelpers.importPodcasts()
  }
}
