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
        ForEach(viewModel.podcastEpisodes) { podcastEpisode in
          NavigationLink(
            value: Navigation.Destination.upNextEpisode(podcastEpisode),
            label: {
              EpisodeListView(
                viewModel: SelectableListItemModel(
                  isSelected: $viewModel.episodeList.isSelected[podcastEpisode.id],
                  item: podcastEpisode,
                  isSelecting: viewModel.isEditing
                )
              )
            }
          )
          .episodeListRow()
          .upNextSwipeActions(viewModel: viewModel, podcastEpisode: podcastEpisode)
          .upNextContextMenu(viewModel: viewModel, podcastEpisode: podcastEpisode)
        }
        .onMove(perform: viewModel.moveItem)
      }
      .refreshable { viewModel.refreshQueue() }
      .navigationTitle("Up Next")
      .environment(\.editMode, $viewModel.editMode)
      .animation(.default, value: viewModel.podcastEpisodes)
      .upNextToolbar(viewModel: viewModel)
    }
    .task(viewModel.execute)
  }
}

#if DEBUG
#Preview {
  UpNextView()
    .preview()
    .task { try? await PreviewHelpers.populateQueue() }
}
#endif
