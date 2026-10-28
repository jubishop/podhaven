// Copyright Justin Bishop, 2025

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
      if sharedState.isOnDeck(episode) {
        switch sharedState.playbackStatus {
        case .playing, .waiting:
          AppIcon.episodePlaying.label
            .labelStyle(.iconOnly)
        case .paused, .loading, .stopped:
          AppIcon.episodePaused.label
            .labelStyle(.iconOnly)
        }
      } else if episode.queueOrder == 0 {
        AppIcon.episodeQueuedAtTop.label
          .labelStyle(.iconOnly)
      } else {
        AppIcon.episodeQueued.label
          .labelStyle(.iconOnly)
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
            innerRadiusRatio: 0.4
          )
          .frame(width: iconSize, height: iconSize)
        } else {
          AppIcon.waiting
            .label("Waiting to Download")
            .labelStyle(.iconOnly)
        }
      } else {
        (episode.saveInCache
          ? AppIcon.episodeSavedInCache
          : AppIcon.episodeCached)
          .label
          .labelStyle(.iconOnly)
          .opacity(episode.cacheStatus == .cached ? 1 : 0)
      }

      if episode.currentTime.safe.seconds > 0, episode.duration.safe.seconds > 0 {
        let progress = episode.currentTime.safe.seconds / episode.duration.safe.seconds
        CircularProgressView(
          colorAmounts: [AppIcon.episodeFinished.color(for: colorScheme): progress],
          innerRadiusRatio: 0.4
        )
        .frame(width: iconSize, height: iconSize)
      } else {
        AppIcon.episodeFinished.label
          .labelStyle(.iconOnly)
          .opacity(episode.finished && !sharedState.isOnDeck(episode) ? 1 : 0)
      }
    }
    .font(.system(size: iconSize))
  }
}
