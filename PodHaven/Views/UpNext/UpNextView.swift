// Copyright Justin Bishop, 2025

import FactoryKit
import SwiftUI

struct UpNextView: View {
  @DynamicInjected(\.alert) private var alert
  @InjectedObservable(\.navigation) private var navigation

  @State private var viewModel = UpNextViewModel()

  var body: some View {
    IdentifiableNavigationStack(manager: navigation.upNext) {
      List {
        ForEach(viewModel.episodeList.filteredEntries) { podcastEpisode in
          upNextListView(podcastEpisode)
            .episodeListRow()
            .episodeSwipeActions(viewModel: viewModel, episode: podcastEpisode)
            .episodeContextMenu(viewModel: viewModel, episode: podcastEpisode)
        }
        .onMove(perform: viewModel.moveEpisode)
      }
      .playBarSafeAreaInset()
      .refreshable { viewModel.refreshQueue() }
      .navigationTitle("Up Next")
      .environment(\.editMode, $viewModel.editMode)
      .animation(.default, value: viewModel.episodeList.filteredEntries)
      .toolbar {
        if !viewModel.isSelecting {
          ToolbarItem(placement: .topBarLeading) {
            Text(viewModel.totalQueueDuration.shortDescription)
              .font(.caption)
              .foregroundStyle(.secondary)
              .fixedSize()
          }
          .sharedBackgroundVisibility(.hidden)

          ToolbarItem(placement: .topBarTrailing) {
            Menu("Sort") {
              ForEach(viewModel.allSortMethods, id: \.self) { method in
                Button(
                  action: { viewModel.sort(by: method) },
                  label: { Label(method.rawValue, systemImage: method.systemImageName) }
                )
                .tint(method.menuIconColor)
              }
            }
          }
        }

        selectableEpisodesToolbarItems(
          viewModel: viewModel,
          episodeList: viewModel.episodeList,
          selectText: "Edit"
        )
      }
    }
    .task(viewModel.execute)
  }

  @ViewBuilder
  func upNextListView(_ podcastEpisode: PodcastEpisode) -> some View {
    let episodeListView = EpisodeListView(
      episode: podcastEpisode,
      isSelecting: viewModel.isSelecting,
      isSelected: $viewModel.episodeList.isSelected[podcastEpisode.id]
    )

    if viewModel.isSelecting {
      episodeListView
    } else {
      NavigationLink(
        value: Navigation.Destination.upNextEpisode(podcastEpisode),
        label: { episodeListView }
      )
    }
  }
}

#if DEBUG
#Preview {
  UpNextView()
    .preview()
    .task { try? await PreviewHelpers.populateQueue() }
}
#endif
