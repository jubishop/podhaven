// Copyright Justin Bishop, 2024

import SwiftUI

struct SettingsView: View {
  @State private var navigation = Navigation.shared

  var body: some View {
    NavigationStack(path: $navigation.settingsPath) {
      Form {
        Section("Importing / Exporting") {
          NavigationLink(
            value: NavigationView { OPMLView() },
            label: { Text("OPML") }
          )
        }

        #if DEBUG
          Section("Debugging") {
            Button("Clear DB") {
              Task {
                try AppDB.shared.db.write { db in
                  try Podcast.deleteAll(db)
                }
              }
            }
            Button(
              action: {
                Task { @PlayActor in PlayManager.shared.stop() }
              },
              label: { Text("Stop Playing") }
            )
            Button(
              action: {
                Task { await playInvalidMedia() }
              },
              label: {
                Text("Load Invalid Episode")
              }
            )
          }
        #endif
      }
      .navigationTitle("Settings")
      .navigationDestination(for: NavigationView.self) { view in view() }
    }
  }

  #if DEBUG
    func playInvalidMedia() async {
      guard
        let podcastEpisode = try? await Repo.shared.db.read({ db in
          try? Episode
            .including(required: Episode.podcast)
            .shuffled()
            .asRequest(of: PodcastEpisode.self)
            .fetchOne(db)
        })
      else {
        Alert.shared("No episodes in DB")
        return
      }
      await PlayManager.shared.load(
        PodcastEpisode(
          podcast: podcastEpisode.podcast,
          episode: Episode(
            id: 1,
            from: UnsavedEpisode(
              guid: "guid",
              media: URL(string: "https://notreal.com/hi.mp3")!,
              title: "Stupid Tech Talky Talky"
            )
          )
        )
      )
    }
  #endif
}

#Preview {
  Preview { SettingsView() }
}
