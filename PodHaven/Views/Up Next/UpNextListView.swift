// Copyright Justin Bishop, 2025

import NukeUI
import SwiftUI

struct UpNextListView: View {
  private let viewModel: UpNextListViewModel

  init(viewModel: UpNextListViewModel) {
    self.viewModel = viewModel
  }

  var body: some View {
    HStack(spacing: 12) {
      if viewModel.isEditing {
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

      LazyImage(url: viewModel.podcastEpisode.image) { state in
        if let image = state.image {
          image
            .resizable()
            .aspectRatio(contentMode: .fill)
        } else {
          Rectangle()
            .fill(Color.gray.opacity(0.3))
        }
      }
      .frame(width: 60, height: 60)
      .clipped()
      .cornerRadius(8)

      VStack(alignment: .leading, spacing: 4) {
        Text(viewModel.episode.title)
          .lineLimit(2)
          .font(.body)
          .multilineTextAlignment(.leading)

        HStack {
          HStack(spacing: 4) {
            Image(systemName: "calendar")
              .font(.caption2)
              .foregroundColor(.secondary)
            Text(viewModel.episode.pubDate.usShort)
              .font(.caption)
              .foregroundColor(.secondary)
          }

          Spacer()

          if viewModel.episode.cachedMediaURL != nil {
            Image(systemName: "arrow.down.circle.fill")
              .font(.caption2)
              .foregroundColor(.green)
          }

          Spacer()

          HStack(spacing: 4) {
            Image(systemName: "clock")
              .font(.caption2)
              .foregroundColor(.secondary)
            Text(viewModel.episode.duration.shortDescription)
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
  @Previewable @State var podcastEpisode: PodcastEpisode?
  @Previewable @State var editMode: EditMode = .inactive
  @Previewable @State var selected: Bool = false

  NavigationStack {
    if let podcastEpisode {
      VStack(spacing: 40) {
        UpNextListView(
          viewModel: UpNextListViewModel(
            isSelected: $selected,
            podcastEpisode: podcastEpisode,
            editMode: editMode
          )
        )
        Divider()
        Button(
          action: {
            editMode = editMode == .active ? .inactive : .active
          },
          label: {
            Text("Swap edit mode")
          }
        )
      }
    } else {
      Text("No episodes in DB")
    }
  }
  .preview()
  .task {
    podcastEpisode = try? await PreviewHelpers.loadPodcastEpisode()
  }
}
#endif
