// Copyright Justin Bishop, 2025

import FactoryKit
import Logging
import SwiftUI

struct SelectablePodcastsGridView: View {
  @DynamicInjected(\.alert) private var alert
  @DynamicInjected(\.navigation) private var navigation

  @State private var viewModel: SelectablePodcastsGridViewModel

  private static let log = Log.as(LogSubsystem.PodcastsView.standard)

  init(viewModel: SelectablePodcastsGridViewModel) {
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
          ForEach(SelectablePodcastsGridViewModel.SortMethod.allCases, id: \.self) { method in
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
        let podcast = podcastWithLatestEpisodeDates.podcast

        NavigationLink(
          value: Navigation.Podcasts.Destination.podcast(podcast),
          label: {
            SelectablePodcastGridItem(
              viewModel: SelectableListItemModel<Podcast>(
                isSelected: $viewModel.podcastList.isSelected[podcastWithLatestEpisodeDates],
                item: podcast,
                isSelecting: viewModel.isSelecting
              )
            )
            .contextMenu {
              Button(
                action: { viewModel.queueLatestEpisodeToTop(podcast.id) },
                label: {
                  Label(
                    "Queue Latest To Top",
                    systemImage: "text.line.first.and.arrowtriangle.forward"
                  )
                }
              )

              Button(
                action: { viewModel.queueLatestEpisodeToBottom(podcast.id) },
                label: {
                  Label(
                    "Queue Latest To Bottom",
                    systemImage: "text.line.last.and.arrowtriangle.forward"
                  )
                }
              )

              Button(
                action: { viewModel.deletePodcast(podcast.id) },
                label: { Label("Delete", systemImage: "trash") }
              )

              if podcast.subscribed {
                Button(
                  action: { viewModel.unsubscribePodcast(podcast.id) },
                  label: { Label("Unsubscribe", systemImage: "minus.circle") }
                )
              } else {
                Button(
                  action: { viewModel.subscribePodcast(podcast.id) },
                  label: { Label("Subscribe", systemImage: "plus.circle") }
                )
              }
            }
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
        Self.log.error(error)
        if ErrorKit.baseError(for: error) is CancellationError { return }
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
          Button("Select") {
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
    SelectablePodcastsGridView(
      viewModel: SelectablePodcastsGridViewModel(title: "Preview Podcasts")
    )
  }
  .preview()
  .task {
    try! await PreviewHelpers.importPodcasts()
  }
}
#endif
