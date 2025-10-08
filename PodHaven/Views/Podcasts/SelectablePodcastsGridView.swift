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
        imageName: AppIcon.filter.systemImageName
      )

      Menu("Sort by") {
        ForEach(viewModel.allSortMethods, id: \.self) { method in
          Button(
            action: { viewModel.currentSortMethod = method },
            label: { Label(method.rawValue, systemImage: method.systemImageName) }
          )
          .tint(method.menuIconColor)
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
          value: Navigation.Destination.podcast(DisplayedPodcast(podcast)),
          label: {
            VStack {
              SelectableSquareImage(
                image: podcast.image,
                sizeConstraint: .width,
                isSelected: $viewModel.podcastList.isSelected[podcast.id],
                isSelecting: viewModel.isSelecting
              )
              Text(podcast.title)
                .font(.caption)
                .lineLimit(1)
            }
            .selectablePodcastsGridContextMenu(
              viewModel: viewModel,
              podcast: podcast
            )
          }
        )
        .buttonStyle(.plain)
      }
      .padding()
    }
    .navigationTitle(viewModel.title)
    .refreshable {
      do {
        try await viewModel.refreshPodcasts()
      } catch {
        Self.log.error(error)
        guard ErrorKit.isRemarkable(error) else { return }
        alert(ErrorKit.coreMessage(for: error))
      }
    }
    .selectablePodcastsGridToolbar(viewModel: viewModel)
    .task(viewModel.execute)
  }
}
