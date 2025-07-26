// Copyright Justin Bishop, 2025

import SwiftUI

typealias EpisodeListViewModel = SelectableListItemModel<Episode>

struct EpisodeListView: View {
  private let viewModel: EpisodeListViewModel

  init(viewModel: EpisodeListViewModel) {
    self.viewModel = viewModel
  }

  var body: some View {
    HStack(spacing: 12) {
      if viewModel.isSelecting {
        Button(
          action: { viewModel.isSelected.wrappedValue.toggle() },
          label: {
            Image(
              systemName: viewModel.isSelected.wrappedValue
                ? "checkmark.circle.fill" : "circle"
            )
          }
        )
        .buttonStyle(BorderlessButtonStyle())
      }

      VStack(alignment: .leading, spacing: 4) {
        Text(viewModel.item.title)
          .lineLimit(2)
          .font(.body)
          .multilineTextAlignment(.leading)

        HStack {
          HStack(spacing: 4) {
            Image(systemName: "calendar")
              .font(.caption2)
              .foregroundColor(.secondary)
            Text(viewModel.item.pubDate.usShort)
              .font(.caption)
              .foregroundColor(.secondary)
          }

          Spacer()

          HStack(spacing: 4) {
            Image(systemName: "clock")
              .font(.caption2)
              .foregroundColor(.secondary)
            Text(viewModel.item.duration.shortDescription)
              .font(.caption)
              .foregroundColor(.secondary)
          }
        }
      }

      Spacer()
    }
  }
}

#if DEBUG
#Preview {
  @Previewable @State var episode: Episode?
  @Previewable @State var selectedEpisode: Episode?
  @Previewable @State var isSelected: Bool = false

  List {
    if let episode {
      EpisodeListView(
        viewModel: EpisodeListViewModel(
          isSelected: .constant(false),
          item: episode,
          isSelecting: false
        )
      )
    }
    if let selectedEpisode {
      EpisodeListView(
        viewModel: EpisodeListViewModel(
          isSelected: $isSelected,
          item: selectedEpisode,
          isSelecting: true
        )
      )
    }
  }
  .preview()
  .task {
    episode = try? await PreviewHelpers.loadEpisode()
    selectedEpisode = try? await PreviewHelpers.loadEpisode()
  }
}
#endif
