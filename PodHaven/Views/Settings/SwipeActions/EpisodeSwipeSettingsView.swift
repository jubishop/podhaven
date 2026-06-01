// Copyright Justin Bishop, 2026

import SwiftUI

struct EpisodeSwipeSettingsView: View {
  @State private var viewModel = EpisodeSwipeSettingsViewModel()

  var body: some View {
    List {
      Section {
        ForEach(viewModel.actions) { action in
          Self.icon(for: action).label(action.title)
        }
        .onMove(perform: viewModel.move)
        .onDelete(perform: viewModel.delete)
        .deleteDisabled(viewModel.actions.count <= 1)
      } footer: {
        Text(
          """
          Choose up to \(EpisodeSwipeSettingsViewModel.maxActions) actions to show when you \
          swipe an episode from right to left, and drag to reorder them. \
          The right-swipe queue actions are fixed.
          """
        )
      }

      if !viewModel.addableActions.isEmpty {
        Section("Add Action") {
          ForEach(viewModel.addableActions) { action in
            Button {
              viewModel.add(action)
            } label: {
              Self.icon(for: action).label(action.title)
            }
          }
        }
      }
    }
    .navigationTitle("Swipe Left Actions")
    .toolbar {
      ToolbarItem(placement: .topBarTrailing) {
        EditButton()
      }
    }
  }

  private static func icon(for action: UserSettings.EpisodeSwipeAction) -> AppIcon {
    switch action {
    case .playPause: .playNow
    case .rate: .rateEpisode
    case .markFinished: .markEpisodeFinished
    case .cache: .cacheEpisode
    case .addTag: .addTag
    }
  }
}

#if DEBUG
#Preview {
  NavigationStack {
    EpisodeSwipeSettingsView()
  }
  .preview()
}
#endif
