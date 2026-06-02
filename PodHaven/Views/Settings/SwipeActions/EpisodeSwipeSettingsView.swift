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
        .disabled(!viewModel.canAddMore)
      }

      Section {
        SwipePreview(actions: viewModel.previewActions)
          .listRowInsets(EdgeInsets())
      } header: {
        Text("Preview")
      } footer: {
        Text(
          """
          Swiping an episode from right to left reveals these actions. \
          The action at the top of the list appears on the far right, \
          where a full swipe triggers it.
          """
        )
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
    case .saveInCache: .saveEpisodeInCache
    case .tag: .tag
    }
  }

  // A mock episode row frozen mid-swipe: a placeholder cell on the left with
  // the configured actions revealed on the right, in their on-screen order.
  private struct SwipePreview: View {
    @Environment(\.colorScheme) private var colorScheme

    let actions: [UserSettings.EpisodeSwipeAction]

    var body: some View {
      HStack(spacing: 0) {
        episodeCell
        ForEach(actions) { action in
          button(for: action)
        }
      }
      .frame(height: 64)
    }

    // Flexible placeholder content (no fixed widths) so the cell compresses to
    // whatever space the action buttons leave, keeping every button fully on
    // screen instead of letting the last one spill past the row's edge.
    private var episodeCell: some View {
      HStack(spacing: 10) {
        RoundedRectangle(cornerRadius: 6)
          .fill(.quaternary)
          .frame(width: 36, height: 36)
        VStack(alignment: .leading, spacing: 6) {
          Capsule().fill(.quaternary).frame(height: 9)
          Capsule().fill(.quaternary).frame(height: 9).padding(.trailing, 28)
        }
        Spacer(minLength: 0)
      }
      .padding(.horizontal, 14)
      .frame(maxWidth: .infinity, maxHeight: .infinity)
      .background(Color(.secondarySystemGroupedBackground))
    }

    private func button(for action: UserSettings.EpisodeSwipeAction) -> some View {
      let icon = EpisodeSwipeSettingsView.icon(for: action)
      return VStack(spacing: 4) {
        icon.rawImage
        Text(action.title)
          .font(.caption2)
          .lineLimit(1)
          .minimumScaleFactor(0.6)
      }
      .foregroundStyle(.white)
      .padding(.horizontal, 4)
      .frame(width: 76)
      .frame(maxHeight: .infinity)
      .background(icon.color(for: colorScheme))
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
