// Copyright Justin Bishop, 2025

import Charts
import CoreMedia
import FactoryKit
import Foundation
import OrderedCollections
import SwiftUI

struct StatusIconColumn<Episode: EpisodeListable>: View {
  @Environment(\.colorScheme) private var colorScheme

  @DynamicInjected(\.sharedState) private var sharedState

  let episode: Episode
  let iconSpacing: CGFloat
  let iconSize: CGFloat

  var body: some View {
    VStack(spacing: iconSpacing) {
      if sharedState.onDeck?.id == episode.episodeID {
        switch sharedState.playbackStatus {
        case .playing, .waiting:
          AppIcon.episodePlaying.image
        case .paused, .loading, .stopped:
          AppIcon.episodePaused.image
        }
      } else if episode.queueOrder == 0 {
        AppIcon.episodeQueuedAtTop.image
      } else {
        AppIcon.episodeQueued.image
          .opacity(episode.queued ? 1 : 0)
      }

      if episode.cacheStatus == .caching,
        let episodeID = episode.episodeID
      {
        if let progress = sharedState.downloadProgress[episodeID] {
          let color =
            episode.saveInCache
            ? AppIcon.episodeSavedInCache.color(for: colorScheme)
            : AppIcon.episodeCached.color(for: colorScheme)
          CircularProgressView(
            colorAmounts: [color: progress],
            innerRadius: .ratio(0.4)
          )
          .frame(width: iconSize, height: iconSize)
        } else {
          AppIcon.waiting.image
        }
      } else {
        (episode.saveInCache
          ? AppIcon.episodeSavedInCache.image
          : AppIcon.episodeCached.image)
          .opacity(episode.cacheStatus == .cached ? 1 : 0)
      }

      if episode.currentTime.safe.seconds > 0, episode.duration.safe.seconds > 0 {
        let progress = episode.currentTime.safe.seconds / episode.duration.safe.seconds
        CircularProgressView(
          colorAmounts: [AppIcon.episodeFinished.color(for: colorScheme): progress],
          innerRadius: .ratio(0.4)
        )
        .frame(width: iconSize, height: iconSize)
      } else {
        AppIcon.episodeFinished.image
          .opacity(episode.finished ? 1 : 0)
      }
    }
    .font(.system(size: iconSize))
  }
}
