// Copyright Justin Bishop, 2025

import SwiftUI

struct DebugSection: View {
  var body: some View {
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
          Task { try await playInvalidMedia() }
        },
        label: {
          Text("Load Invalid Episode")
        }
      )
      Button(
        action: {
          Task { try await PreviewHelpers.populateQueue() }
        },
        label: {
          Text("Populate Queue")
        }
      )
    }
  }

  func playInvalidMedia() async throws {
    let podcastEpisode = try await PreviewHelpers.loadPodcastEpisode()
    await PlayManager.shared.load(
      PodcastEpisode(
        podcast: podcastEpisode.podcast,
        episode: Episode(
          from: try UnsavedEpisode(
            guid: "guid",
            title: "Stupid Tech Talky Talky",
            media: URL(string: "https://notreal.com/hi.mp3")!
          )
        )
      )
    )
  }
}

#Preview {
  DebugSection().preview()
}
