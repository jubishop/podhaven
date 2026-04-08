// Copyright Justin Bishop, 2026

import CoreMedia
import FactoryKit
import Nuke
import SwiftUI

struct ShareEpisodeButton<E: EpisodeListable>: View {
  let episode: E

  @ObservationIgnored @DynamicInjected(\.imagePipeline) private var imagePipeline
  @ObservationIgnored @DynamicInjected(\.sharedState) private var sharedState

  private var shareURL: URL {
    guard let url = ShareURL.episode(feedURL: episode.feedURL, guid: episode.mediaGUID.guid)
    else { Assert.fatal("Failed to build share URL for episode: \(episode.toString)") }
    return url
  }

  private func timedShareURL(startTimeSeconds: Int) -> URL {
    guard
      let url = ShareURL.episode(
        feedURL: episode.feedURL,
        guid: episode.mediaGUID.guid,
        startTime: startTimeSeconds
      )
    else { Assert.fatal("Failed to build timed share URL for episode: \(episode.toString)") }
    return url
  }

  private var isOnDeck: Bool {
    guard let episodeID = episode.episodeID else { return false }
    return sharedState.onDeck?.id == episodeID
  }

  private var currentTime: CMTime? {
    guard isOnDeck else { return nil }
    let time = sharedState.onDeck?.currentTime ?? .zero
    guard time.safe.seconds > 0 else { return nil }
    return time
  }

  private var sharePreview: SharePreview<Image, Image> {
    let image = cachedArtwork
    return SharePreview(Text(episode.title), image: image, icon: image)
  }

  private var cachedArtwork: Image {
    let request = ImageRequest(url: episode.image)
    if let container = imagePipeline.cache[request] {
      return Image(uiImage: container.image)
    }
    return AppIcon.showEpisode.rawImage
  }

  var body: some View {
    if let currentTime {
      shareMenu(baseURL: shareURL, currentTime: currentTime)
    } else {
      ShareLink(item: shareURL, preview: sharePreview) {
        AppIcon.shareEpisode.image
      }
    }
  }

  @ViewBuilder
  private func shareMenu(baseURL: URL, currentTime: CMTime) -> some View {
    Menu {
      ShareLink(item: baseURL, preview: sharePreview) {
        AppIcon.shareEpisodeFromStart.rawLabel
      }
      ShareLink(
        item: timedShareURL(startTimeSeconds: Int(currentTime.safe.seconds)),
        preview: sharePreview
      ) {
        AppIcon.shareEpisode.rawLabel("Share from \(currentTime.description)")
      }
    } label: {
      AppIcon.shareEpisode.image
    }
  }
}
