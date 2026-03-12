// Copyright Justin Bishop, 2026

import AVFoundation
import FactoryKit
import Foundation
import GRDB
import Logging
import Nuke
import Tagged
import UIKit
import WidgetKit

extension Container {
  var widgetSnapshotWriter: Factory<WidgetSnapshotWriter> {
    Factory(self) { WidgetSnapshotWriter() }.scope(.cached)
  }
}

final class WidgetSnapshotWriter: Sendable {
  private var fileManager: any FileManaging { Container.shared.fileManager() }
  private var sharedState: SharedState { Container.shared.sharedState() }
  private var sleeper: any Sleepable { Container.shared.sleeper() }
  private var userSettings: UserSettings { Container.shared.userSettings() }
  private var imagePipeline: ImagePipeline { Container.shared.imagePipeline() }
  private var observatory: Observatory { Container.shared.observatory() }

  private static let log = Log.as(LogSubsystem.Widget.writer)

  private let pendingReloadKinds = ThreadSafe<Set<String>>([])
  private let debounce = Debounce(duration: .milliseconds(250))
  private let queueWidgetEpisodes = ThreadSafe<[QueueWidgetEpisode]>([])
  private let lastOnDeck = ThreadSafe<OnDeck?>(nil)
  private let lastPlaybackStatus = ThreadSafe<PlaybackStatus>(.stopped)
  private let heartbeatTask = ThreadSafe<Task<Void, Never>?>(nil)

  // MARK: - Start

  func start() {
    guard Function.neverCalled() else { return }

    Task { [weak self] in
      guard let self else { return }

      for await onDeck in sharedState.$onDeck.stream() {
        let changed: Bool = lastOnDeck { last in
          defer { last = onDeck }
          guard let onDeck else { return last != nil }
          guard let last else { return true }
          return !onDeck.widgetEquals(last)
        }
        if changed {
          scheduleWrite(
            reloadKinds: [WidgetInfo.nowPlayingKind, WidgetInfo.lockScreenNowPlayingKind])
        }
      }
    }

    Task { [weak self] in
      guard let self else { return }

      for await status in sharedState.$playbackStatus.stream() {
        let changed: Bool = lastPlaybackStatus { last in
          defer { last = status }
          return status != last
        }
        guard changed else { continue }
        WidgetInfo.playbackStatus = status
        reloadWidgets(kinds: [WidgetInfo.nowPlayingKind, WidgetInfo.lockScreenNowPlayingKind])

        if status.playing {
          startHeartbeat()
        } else {
          stopHeartbeat()
        }
      }
    }

    Task { [weak self] in
      guard let self else { return }

      do {
        for try await episodes in observatory.queueWidgetEpisodes() {
          queueWidgetEpisodes(episodes)
          scheduleWrite(reloadKinds: [WidgetInfo.queueKind])
        }
      } catch {
        Self.log.caughtError("start: queueWidgetEpisodes observation failed", error)
      }
    }

    Task { [weak self] in
      guard let self else { return }

      for await _ in userSettings.$alwaysShowPodcastImageInUpNext.stream() {
        scheduleWrite(reloadKinds: [WidgetInfo.queueKind])
      }
    }

    Task { [weak self] in
      guard let self else { return }

      for await _ in userSettings.$skipForwardInterval.stream() {
        scheduleWrite(reloadKinds: [WidgetInfo.nowPlayingKind])
      }
    }

    Task { [weak self] in
      guard let self else { return }

      for await _ in userSettings.$skipBackwardInterval.stream() {
        scheduleWrite(reloadKinds: [WidgetInfo.nowPlayingKind])
      }
    }
  }

  // MARK: - Coalesced Writing

  private func scheduleWrite(reloadKinds: Set<String>) {
    pendingReloadKinds { $0.formUnion(reloadKinds) }
    debounce { [weak self] in
      guard let self else { return }
      await flush()
    }
  }

  private func flush() async {
    await writeSnapshot()

    // If cancelled during the write, leave pending kinds for the next cycle.
    guard !Task.isCancelled else { return }

    let kindsToReload: Set<String> = pendingReloadKinds { kinds in
      defer { kinds.removeAll() }
      return kinds
    }

    guard !kindsToReload.isEmpty else { return }
    reloadWidgets(kinds: kindsToReload)
  }

  // MARK: - Snapshot Building

  private func writeSnapshot() async {
    let nowPlaying: WidgetSnapshot.NowPlaying? =
      if let onDeck = sharedState.onDeck {
        WidgetSnapshot.NowPlaying(
          episodeID: onDeck.id.rawValue,
          episodeTitle: onDeck.title,
          podcastTitle: onDeck.podcastTitle,
          pubDateTimestamp: onDeck.pubDate.timeIntervalSince1970,
          durationSeconds: onDeck.duration.seconds,
          artworkBase64: encodeArtwork(onDeck.artwork, maxPixels: maxNowPlayingArtworkPixels)
        )
      } else {
        nil
      }

    let episodes = Array(queueWidgetEpisodes().prefix(5))
    let showPodcastImage = userSettings.alwaysShowPodcastImageInUpNext
    let queueArtwork = await loadQueueArtwork(for: episodes, showPodcastImage: showPodcastImage)

    // If cancelled during artwork loading, bail before writing a stale snapshot.
    guard !Task.isCancelled else { return }

    let queueItems = episodes.enumerated()
      .map { index, episode in
        WidgetSnapshot.QueueItem(
          episodeID: episode.id.rawValue,
          episodeTitle: episode.title,
          pubDateTimestamp: episode.pubDate.timeIntervalSince1970,
          durationSeconds: episode.duration.seconds,
          artworkBase64: encodeArtwork(queueArtwork[index], maxPixels: maxQueueArtworkPixels)
        )
      }

    let snapshot = WidgetSnapshot(
      schemaVersion: WidgetSnapshot.currentSchemaVersion,
      nowPlaying: nowPlaying,
      queue: queueItems,
      queueTotalCount: queueWidgetEpisodes().count,
      skipForwardInterval: Int(userSettings.skipForwardInterval),
      skipBackwardInterval: Int(userSettings.skipBackwardInterval),
      updatedAt: Date()
    )

    do {
      let data = try JSONEncoder().encode(snapshot)
      try await fileManager.writeData(data, to: WidgetInfo.snapshotURL)
      Self.log.debug("Wrote widget snapshot (\(data.count) bytes)")
    } catch {
      Self.log.caughtError("writeSnapshot: failed to encode/write widget snapshot", error)
    }
  }

  private func loadQueueArtwork(
    for episodes: [QueueWidgetEpisode],
    showPodcastImage: Bool
  ) async -> [UIImage?] {
    await withTaskGroup(of: (Int, UIImage?).self, returning: [UIImage?].self) { group in
      for (index, episode) in episodes.enumerated() {
        group.addTask { [imagePipeline] in
          let url = showPodcastImage ? episode.podcastImage : episode.image
          do {
            let image = try await imagePipeline.image(for: url)
            return (index, image)
          } catch {
            Self.log.caughtError(
              "loadQueueArtwork: failed to load image \(url) for episode \(episode.id)",
              error,
              remarkable: .info
            )
            return (index, nil)
          }
        }
      }

      var results = [UIImage?](capacity: episodes.count)
      for _ in episodes { results.append(nil) }
      for await (index, image) in group {
        results[index] = image
      }
      return results
    }
  }

  // MARK: - Artwork Encoding

  // Now-playing artwork: largest view is 80pt (systemMedium) at 3x = 240px.
  private let maxNowPlayingArtworkPixels: CGFloat = 240

  // Queue artwork: ~28pt thumbnails at 3x = ~96px (rounded up for safety).
  private let maxQueueArtworkPixels: CGFloat = 96

  private func encodeArtwork(_ image: UIImage?, maxPixels: CGFloat) -> String? {
    guard let image else { return nil }
    let downsized = downsample(image, maxPixels: maxPixels)
    guard let jpegData = downsized.jpegData(compressionQuality: 1.0) else { return nil }
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

  // MARK: - Heartbeat

  // Reload the now-playing timeline periodically while playing so the
  // widget's fallback "paused" entry keeps getting pushed forward. These
  // reloads are free while the app holds an active audio session.
  private func startHeartbeat() {
    stopHeartbeat()
    let task = Task { [weak self] in
      while !Task.isCancelled {
        guard let self else { return }
        try? await sleeper.sleep(for: .seconds(240))
        guard !Task.isCancelled else { return }
        reloadWidgets(kinds: [WidgetInfo.nowPlayingKind])
      }
    }
    heartbeatTask(task)
  }

  private func stopHeartbeat() {
    heartbeatTask { task in
      task?.cancel()
      task = nil
    }
  }

  // MARK: - Widget Reloading

  private func reloadWidgets(kinds: Set<String>) {
    WidgetCenter.shared.getCurrentConfigurations { result in
      let configurations: [WidgetKit.WidgetInfo]
      switch result {
      case .success(let value):
        configurations = value
      case .failure(let error):
        Self.log.caughtError("reloadWidgets: failed to get current widget configurations", error)
        return
      }

      let placedKinds = Set(configurations.map(\.kind))

      for kind in kinds where placedKinds.contains(kind) {
        Self.log.debug("Reloading timeline for \(kind)")
        WidgetCenter.shared.reloadTimelines(ofKind: kind)
      }
    }
  }
}
