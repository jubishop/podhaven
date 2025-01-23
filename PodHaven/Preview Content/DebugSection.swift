// Copyright Justin Bishop, 2025

import Factory
import SwiftUI

struct DebugSection: View {
  @Environment(Alert.self) var alert

  private let playManager = Container.shared.playManager()

  var body: some View {
    Section("Debugging") {
      Button("Clear DB") {
        Task {
          try AppDB.onDisk.db.write { db in
            try Podcast.deleteAll(db)
          }
        }
      }
      Button(
        action: {
          Task {
            do {
              try await playInvalidMedia()
            } catch {
              alert.andReport(error)
            }
          }
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
    try await playManager.load(
      PodcastEpisode(
        podcast: podcastEpisode.podcast,
        episode: Episode(
          from: try UnsavedEpisode(
            guid: "guid",
            media: URL(string: "https://notreal.com/hi.mp3")!,
            title: "Stupid Tech Talky Talky"
          )
        )
      )
    )
  }
}

#Preview {
  DebugSection()
    .preview()
}
