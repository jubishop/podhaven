// Copyright Justin Bishop, 2026

import AVFoundation
import FactoryKit
import Foundation
import Logging
import Tagged
import UIKit
import WidgetKit

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
    scheduleWrite(reloadKinds: [WidgetInfo.nowPlayingKind])
  }

  func artworkChanged() {
    scheduleWrite(reloadKinds: [WidgetInfo.nowPlayingKind])
  }

  func playbackStatusChanged() {
    scheduleWrite(reloadKinds: [WidgetInfo.nowPlayingKind])
  }

  func currentTimeChanged() {
    let now = Date()
    guard now.timeIntervalSince(lastCurrentTimeWrite) >= 30 else { return }
    lastCurrentTimeWrite = now
    scheduleWrite(reloadKinds: [WidgetInfo.nowPlayingKind])
  }

  func queueChanged() {
    scheduleWrite(reloadKinds: [WidgetInfo.queueKind])
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
          playbackStatus: playbackStatus.widgetStatus,
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
      queueTotalCount: queuedEpisodes.count,
      updatedAt: Date()
    )

    do {
      let data = try JSONEncoder().encode(snapshot)
      try data.write(to: WidgetInfo.snapshotURL, options: .atomic)
      Self.log.debug("Wrote widget snapshot (\(data.count) bytes)")
    } catch {
      Self.log.error(error)
      return
    }

    reloadWidgets(kinds: reloadKinds)
  }

  // MARK: - Artwork Encoding

  // Max pixel size for widget artwork. The largest artwork view is 80pt
  // (systemMedium) at 3x scale = 240px.
  private let maxArtworkPixels: CGFloat = 240

  private func encodeArtwork(_ image: UIImage?) -> String? {
    guard let image else { return nil }
    let downsized = downsample(image, maxPixels: maxArtworkPixels)
    guard let jpegData = downsized.jpegData(compressionQuality: 0.7) else { return nil }
    return jpegData.base64EncodedString()
  }

  private func downsample(_ image: UIImage, maxPixels: CGFloat) -> UIImage {
    let size = image.size
    let scale = image.scale
    let pixelWidth = size.width * scale
    let pixelHeight = size.height * scale

    guard max(pixelWidth, pixelHeight) > maxPixels else { return image }

    let ratio = maxPixels / max(pixelWidth, pixelHeight)
    let targetSize = CGSize(
      width: (pixelWidth * ratio).rounded(.down),
      height: (pixelHeight * ratio).rounded(.down)
    )

    let renderer = UIGraphicsImageRenderer(size: targetSize)
    return renderer.image { _ in
      image.draw(in: CGRect(origin: .zero, size: targetSize))
    }
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
