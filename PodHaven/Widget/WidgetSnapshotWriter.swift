// Copyright Justin Bishop, 2026

import AVFoundation
import FactoryKit
import Foundation
import Logging
import UIKit
import WidgetKit
import Tagged

extension Container {
  var widgetSnapshotWriter: Factory<WidgetSnapshotWriter> {
    Factory(self) { WidgetSnapshotWriter() }.scope(.cached)
  }
}

actor WidgetSnapshotWriter {
  @DynamicInjected(\.sharedState) private var sharedState

  private static let log = Log.as(LogSubsystem.Widget.writer)

  private var pendingReloadKinds: Set<String> = []
  private var coalesceTask: Task<Void, Never>?
  private var lastCurrentTimeWrite: Date = .distantPast

  // MARK: - Snapshot Triggers

  func onDeckChanged() {
    scheduleWrite(reloadKinds: [WidgetConstants.nowPlayingKind])
  }

  func artworkChanged() {
    scheduleWrite(reloadKinds: [WidgetConstants.nowPlayingKind])
  }

  func playbackStatusChanged() {
    scheduleWrite(reloadKinds: [WidgetConstants.nowPlayingKind])
  }

  func currentTimeChanged() {
    let now = Date()
    guard now.timeIntervalSince(lastCurrentTimeWrite) >= 30 else { return }
    lastCurrentTimeWrite = now
    scheduleWrite(reloadKinds: [WidgetConstants.nowPlayingKind])
  }

  func queueChanged() {
    scheduleWrite(reloadKinds: [WidgetConstants.queueKind])
  }

  // MARK: - Coalesced Writing

  private func scheduleWrite(reloadKinds: Set<String>) {
    pendingReloadKinds.formUnion(reloadKinds)

    coalesceTask?.cancel()
    coalesceTask = Task { [weak self] in
      try? await Task.sleep(for: .milliseconds(100))
      guard !Task.isCancelled else { return }
      await self?.flush()
    }
  }

  private func flush() {
    let kindsToReload = pendingReloadKinds
    pendingReloadKinds.removeAll()
    coalesceTask = nil

    writeSnapshot(reloadKinds: kindsToReload)
  }

  // MARK: - Snapshot Building

  private func writeSnapshot(reloadKinds: Set<String>) {
    let onDeck = sharedState.onDeck
    let playbackStatus = sharedState.playbackStatus
    let queuedEpisodes = sharedState.queuedPodcastEpisodes

    let nowPlaying: WidgetSnapshot.NowPlaying? =
      if let onDeck {
        WidgetSnapshot.NowPlaying(
          episodeID: onDeck.id.rawValue,
          episodeTitle: onDeck.title,
          podcastTitle: onDeck.podcastTitle,
          durationSeconds: onDeck.duration.seconds,
          currentTimeSeconds: onDeck.currentTime.seconds,
          playbackStatus: playbackStatus.widgetString,
          artworkBase64: encodeArtwork(onDeck.artwork)
        )
      } else {
        nil
      }

    let queueItems = Array(queuedEpisodes.prefix(5))
      .map { episode in
        WidgetSnapshot.QueueItem(
          episodeID: episode.id.rawValue,
          episodeTitle: episode.title,
          podcastTitle: episode.podcastTitle,
          durationSeconds: episode.duration.seconds
        )
      }

    let snapshot = WidgetSnapshot(
      schemaVersion: WidgetSnapshot.currentSchemaVersion,
      nowPlaying: nowPlaying,
      queue: queueItems,
      updatedAt: Date()
    )

    do {
      let data = try JSONEncoder().encode(snapshot)
      try data.write(to: WidgetConstants.snapshotURL, options: .atomic)
      Self.log.debug("Wrote widget snapshot (\(data.count) bytes)")
    } catch {
      Self.log.error(error)
      return
    }

    reloadWidgets(kinds: reloadKinds)
  }

  // MARK: - Artwork Encoding

  private func encodeArtwork(_ image: UIImage?) -> String? {
    guard let image else { return nil }
    guard let jpegData = image.jpegData(compressionQuality: 0.7) else { return nil }
    return jpegData.base64EncodedString()
  }

  // MARK: - Widget Reloading

  private func reloadWidgets(kinds: Set<String>) {
    WidgetCenter.shared.getCurrentConfigurations { result in
      guard case .success(let configurations) = result else { return }

      let placedKinds = Set(configurations.map(\.kind))

      for kind in kinds where placedKinds.contains(kind) {
        Self.log.debug("Reloading timeline for \(kind)")
        WidgetCenter.shared.reloadTimelines(ofKind: kind)
      }
    }
  }
}
