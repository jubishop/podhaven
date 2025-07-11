// Copyright Justin Bishop, 2025

import FactoryKit
import Logging
import SwiftUI

struct StandardPodcastsView: View {
  @DynamicInjected(\.alert) private var alert
  @DynamicInjected(\.navigation) private var navigation

  @State private var viewModel: StandardPodcastsViewModel

  private static let log = Log.as(LogSubsystem.PodcastsView.standard)

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
          value: Navigation.Podcasts.Destination.podcast(
            podcastWithLatestEpisodeDates.podcast
          ),
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
    .refreshable {
      do {
        try await viewModel.refreshPodcasts()
      } catch {
        if ErrorKit.baseError(for: error) is CancellationError { return }
        Self.log.error(error)
        alert(ErrorKit.message(for: error))
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
    .task(viewModel.execute)
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
