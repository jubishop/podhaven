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
        ForEach(viewModel.allSortMethods, id: \.self) { method in
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
          value: Navigation.Destination.podcast(podcast),
          label: {
            SelectableImageGridItem(
              viewModel: SelectableListItemModel(
                isSelected: $viewModel.podcastList.isSelected[podcastWithLatestEpisodeDates],
                item: podcast,
                isSelecting: viewModel.isSelecting
              ),
              size: $gridItemSize
            )
            .selectablePodcastsGridContextMenu(
              viewModel: viewModel,
              podcast: podcast
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
        Self.log.error(error)
        if !ErrorKit.isRemarkable(error) { return }
        alert(ErrorKit.message(for: error))
      }
    }
    .selectablePodcastsGridToolbar(viewModel: viewModel)
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
