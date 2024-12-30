// Copyright Justin Bishop, 2024

import SwiftUI

struct UpNextListView: View {
  @Environment(\.editMode) private var editMode
  @Binding var isSelected: Bool

  let podcastEpisode: PodcastEpisode
  var podcast: Podcast { podcastEpisode.podcast }
  var episode: Episode { podcastEpisode.episode }
  private var isEditing: Bool { editMode?.wrappedValue.isEditing == true }

  var body: some View {
    HStack(spacing: 20) {
      if isEditing {
        Button(
          action: {
            isSelected.toggle()
          },
          label: {
            Image(
              systemName: isSelected ? "checkmark.circle.fill" : "circle"
            )
          }
        )
        .buttonStyle(BorderlessButtonStyle())
      }

      Text(episode.toString)
        .lineLimit(2)

      Spacer()

      if !isEditing {
        Menu(
          content: {
            Button(
              action: {
                Task { @PlayActor in
                  await PlayManager.shared.load(podcastEpisode)
                  PlayManager.shared.play()
                }
              },
              label: { Label("Play Now", systemImage: "play") }
            )

            Button(
              action: {
                Task {
                  try await Repo.shared.unshiftToQueue(episode.id)
                }
              },
              label: { Label("Play Next", systemImage: "square.and.arrow.up") }
            )

            Button(
              action: {
                Task {
                  Navigation.shared.showEpisode(podcastEpisode)
                }
              },
              label: { Label("View Details", systemImage: "info.circle") }
            )

            Button(
              action: {
                Task {
                  try await Repo.shared.dequeue(episode.id)
                }
              },
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
  }
}

#Preview {
  @Previewable @State var podcastEpisode: PodcastEpisode?
  @Previewable @State var editMode: EditMode = .inactive
  @Previewable @State var selected: Bool = false

  Preview {
    NavigationStack {
      Group {
        if let podcastEpisode = podcastEpisode {
          VStack(spacing: 40) {
            UpNextListView(
              isSelected: $selected,
              podcastEpisode: podcastEpisode
            )
            .environment(\.editMode, $editMode)
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
      .task {
        podcastEpisode = try? await Helpers.loadPodcastEpisode()
      }
    }
  }
}
