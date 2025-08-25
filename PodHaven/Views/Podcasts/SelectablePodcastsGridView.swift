// Copyright Justin Bishop, 2025

import FactoryKit
import Logging
import SwiftUI

struct SelectablePodcastsGridView: View {
  @DynamicInjected(\.alert) private var alert
  @DynamicInjected(\.navigation) private var navigation

  @State private var viewModel: SelectablePodcastsGridViewModel
  @State private var gridItemSize: CGFloat = 100

  private static let log = Log.as(LogSubsystem.PodcastsView.standard)

  init(viewModel: SelectablePodcastsGridViewModel) {
    self.viewModel = viewModel
  }

  var body: some View {
    HStack {
      SearchBar(
        text: $viewModel.podcastList.entryFilter,
        placeholder: "Filter podcasts",
        imageName: AppLabel.filter.systemImageName
      )

      Menu("Sort by") {
        ForEach(SelectablePodcastsGridViewModel.SortMethod.allCases, id: \.self) { method in
          Button(method.rawValue) {
            viewModel.currentSortMethod = method
          }
          .disabled(viewModel.currentSortMethod == method)
        }
      }
    }
    .padding(.horizontal)

    ScrollView {
      ItemGrid(items: viewModel.podcastList.filteredEntries) {
        podcastWithLatestEpisodeDates in
        let podcast = podcastWithLatestEpisodeDates.podcast

        NavigationLink(
          value: Navigation.Podcasts.Destination.podcast(podcast),
          label: {
            SelectableImageGridItem(
              viewModel: SelectableListItemModel<Podcast>(
                isSelected: $viewModel.podcastList.isSelected[podcastWithLatestEpisodeDates],
                item: podcast,
                isSelecting: viewModel.isSelecting
              ),
              size: $gridItemSize
            )
            .contextMenu {
              Button(
                action: { viewModel.queueLatestEpisodeToTop(podcast.id) },
                label: {
                  Label(
                    "Queue Latest To Top",
                    systemImage: AppLabel.queueLatestToTop.systemImageName
                  )
                }
              )

              Button(
                action: { viewModel.queueLatestEpisodeToBottom(podcast.id) },
                label: {
                  Label(
                    "Queue Latest To Bottom",
                    systemImage: AppLabel.queueLatestToBottom.systemImageName
                  )
                }
              )

              Button(
                action: { viewModel.deletePodcast(podcast.id) },
                label: { AppLabel.delete.label }
              )

              if podcast.subscribed {
                Button(
                  action: { viewModel.unsubscribePodcast(podcast.id) },
                  label: { AppLabel.unsubscribe.label }
                )
              } else {
                Button(
                  action: { viewModel.subscribePodcast(podcast.id) },
                  label: { AppLabel.subscribe.label }
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
        if !ErrorKit.isRemarkable(error) { return }
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
              AppLabel.moreActions.image
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
