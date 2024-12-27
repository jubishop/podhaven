// Copyright Justin Bishop, 2024

import SwiftUI

struct UpNextListView: View {
  @Environment(\.editMode) private var editMode
  @Binding var isSelected: Bool

  let podcastEpisode: PodcastEpisode
  var podcast: Podcast { podcastEpisode.podcast }
  var episode: Episode { podcastEpisode.episode }

  var body: some View {
    NavigationLink(
      value: podcastEpisode,
      label: {
        HStack(spacing: 20) {
          if editMode?.wrappedValue.isEditing == true {
            Button(
              action: {
                isSelected.toggle()
              },
              label: {
                Image(
                  systemName: isSelected ? "checkmark.circle.fill" : "circle"
                )
                .foregroundColor(isSelected ? .blue : .gray)
              }
            )
            .buttonStyle(BorderlessButtonStyle())
          }
          Text(String(episode.queueOrder ?? -1))
          Text(episode.toString)
        }
      }
    )
  }
}

#Preview {
  struct UpNextListViewPreview: View {
    @State var podcastEpisode: PodcastEpisode?
    @State var editMode: EditMode = .inactive

    var body: some View {
      Group {
        if let podcastEpisode = self.podcastEpisode {
          VStack(spacing: 40) {
            UpNextListView(
              isSelected: .constant(false),
              podcastEpisode: podcastEpisode
            )
            .environment(\.editMode, $editMode)
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
        self.podcastEpisode = try? await Helpers.loadPodcastEpisode()
      }
    }
  }

  return Preview { NavigationStack { UpNextListViewPreview() } }
}
