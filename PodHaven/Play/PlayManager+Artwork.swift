// Copyright Justin Bishop, 2026

import Foundation
import Nuke

extension PlayManager {
  func fetchImage(for podcastEpisode: PodcastEpisode) {
    let imageURL =
      userSettings.alwaysShowPodcastImageForOnDeck
      ? podcastEpisode.podcastImage : podcastEpisode.image
    fetchImage(episodeID: podcastEpisode.id, imageURL: imageURL)
  }

  private func fetchImage(episodeID: Episode.ID, imageURL: URL) {
    imageFetchTask?.cancel()

    imageFetchTask = Task { [weak self, episodeID, imageURL] in
      guard let self else { return }
      do {
        let image = try await imagePipeline.image(for: imageURL)
        guard !Task.isCancelled else { return }

        stateManager.setArtwork(image, for: episodeID)
        NowPlayingInfo.setImage(image)
      } catch {
        Self.log.caughtError(
          "fetchImage: failed to load image \(imageURL) for episode \(episodeID)",
          error
        )
      }
    }
  }

  func refetchOnDeckImage() {
    guard let onDeck = sharedState.onDeck else { return }
    let imageURL =
      userSettings.alwaysShowPodcastImageForOnDeck ? onDeck.podcastImage : onDeck.image
    fetchImage(episodeID: onDeck.id, imageURL: imageURL)
  }

}
