// Copyright Justin Bishop, 2025

import SwiftUI

struct UpNextListView: View {
  private let viewModel: UpNextListViewModel

  init(viewModel: UpNextListViewModel) {
    self.viewModel = viewModel
  }

  var body: some View {
    HStack(spacing: 20) {
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

      Text(viewModel.episode.toString)
        .lineLimit(2)

      Spacer()

      if !viewModel.isEditing {
        Menu(
          content: {
            Button(
              action: viewModel.playNow,
              label: { Label("Play Now", systemImage: "play") }
            )

            Button(
              action: viewModel.playNext,
              label: { Label("Play Next", systemImage: "square.and.arrow.up") }
            )

            Button(
              action: viewModel.viewDetails,
              label: { Label("View Details", systemImage: "info.circle") }
            )

            Button(
              action: viewModel.delete,
              label: { Label("Delete", systemImage: "trash") }
            )
          },
          label: {
            Image(systemName: "ellipsis")
              .font(.title)
              .frame(maxHeight: .infinity)
          }
        )
        .buttonStyle(PlainButtonStyle())
      }
    }
    .fixedSize(horizontal: false, vertical: true)
  }
}

#if DEBUG
#Preview {
  @Previewable @State var podcastEpisode: PodcastEpisode?
  @Previewable @State var editMode: EditMode = .inactive
  @Previewable @State var selected: Bool = false

  NavigationStack {
    if let podcastEpisode = podcastEpisode {
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
