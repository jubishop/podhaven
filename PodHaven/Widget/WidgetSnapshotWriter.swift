// Copyright Justin Bishop, 2026

import CoreMedia
import FactoryKit
import Foundation
import Logging
import Nuke
import Tagged
import UIKit
import WidgetKit

extension Container {
  var controlCenter: Factory<any ControlReloading> {
    Factory(self) { ControlCenter.shared }
  }

  var widgetCenter: Factory<any WidgetReloading> {
    Factory(self) { SystemWidgetCenter() }
  }

  var widgetSnapshotWriter: Factory<WidgetSnapshotWriter> {
    Factory(self) { WidgetSnapshotWriter() }.scope(.cached)
  }
}

final class WidgetSnapshotWriter: Sendable {
  private var controlCenter: any ControlReloading { Container.shared.controlCenter() }
  private var fileManager: any FileManaging { Container.shared.fileManager() }
  private var imagePipeline: ImagePipeline { Container.shared.imagePipeline() }
  private var sharedState: SharedState { Container.shared.sharedState() }
  private var sleeper: any Sleepable { Container.shared.sleeper() }
  private var userSettings: UserSettings { Container.shared.userSettings() }
  private var widgetCenter: any WidgetReloading { Container.shared.widgetCenter() }
  private var widgetState: WidgetState { Container.shared.widgetState() }

  private static let log = Log.as(LogSubsystem.Widget.writer)

  private let nowPlayingDebounce = Debounce(duration: .milliseconds(250))
  private let queueDebounce = Debounce(duration: .seconds(1))
  private let queueWidgetEpisodes = ThreadSafe<[WidgetEpisode]>([])
  private let lastOnDeck = ThreadSafe<OnDeck?>(nil)
  private let lastPlaybackStatus = ThreadSafe<PlaybackStatus>(.stopped)
  private let heartbeatTask = ThreadSafe<Task<Void, Never>?>(nil)
  private let startOnce = Once()

  // MARK: - Start

  func start() {
    startOnce.run {
      Task { [weak self] in
        guard let self else { return }

        // PlayManager has already restored onDeck by the time we start.
        // If nothing is playing, clear any stale snapshot from a prior session.
        if sharedState.onDeck == nil {
          do {
            try fileManager.removeItem(at: WidgetInfo.nowPlayingSnapshotURL)
          } catch {
            Self.log.caughtError(
              "start: failed to remove stale now-playing snapshot",
              error,
              level: { error in
                let nsError = error as NSError
                if nsError.domain == NSCocoaErrorDomain && nsError.code == NSFileNoSuchFileError {
                  return .debug
                }
                return ErrorKit.level(error)
              }
            )
          }
          reloadWidgets(kinds: [WidgetInfo.nowPlayingKind, WidgetInfo.lockScreenNowPlayingKind])
        }

        for await onDeck in sharedState.$onDeck.stream() {
          let changed: Bool = lastOnDeck { last in
            defer { last = onDeck }
            guard let onDeck else { return last != nil }
            guard let last else { return true }
            return !onDeck.widgetEquals(last)
          }
          if changed {
            nowPlayingDebounce { [weak self] in
              guard let self else { return }
              await writeNowPlayingSnapshot()
              reloadWidgets(kinds: [WidgetInfo.nowPlayingKind, WidgetInfo.lockScreenNowPlayingKind])
            }
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
          widgetState.playbackStatus = status
          Self.log.debug("Playback status changed to \(status), reloading play/pause control")
          reloadWidgets(kinds: [WidgetInfo.nowPlayingKind, WidgetInfo.lockScreenNowPlayingKind])
          controlCenter.reloadControls(ofKind: WidgetInfo.playPauseControlKind)

          if status.playing {
            startHeartbeat()
          } else {
            stopHeartbeat()
          }
        }
      }

      Task { [weak self] in
        guard let self else { return }

        for await podcastEpisodes in sharedState.$queuedPodcastEpisodes.stream() {
          let episodes = podcastEpisodes.map(WidgetEpisode.init)
          let changed: Bool = queueWidgetEpisodes { current in
            defer { current = episodes }
            return current != episodes
          }
          guard changed else { continue }
          queueDebounce { [weak self] in
            guard let self else { return }
            await writeQueueSnapshot()
            reloadWidgets(kinds: [WidgetInfo.queueKind])
          }
        }
      }

      Task { [weak self] in
        guard let self else { return }

        for await _ in userSettings.$alwaysShowPodcastImageInUpNext.stream() {
          queueDebounce { [weak self] in
            guard let self else { return }
            await writeQueueSnapshot()
            reloadWidgets(kinds: [WidgetInfo.queueKind])
          }
        }
      }

      Task { [weak self] in
        guard let self else { return }

        for await interval in userSettings.$skipForwardInterval.stream() {
          let intInterval = Int(interval)
          Self.log.debug("Skip forward interval changed to \(intInterval), reloading control")
          widgetState.skipForwardInterval = intInterval
          reloadWidgets(kinds: [WidgetInfo.nowPlayingKind])
          controlCenter.reloadControls(ofKind: WidgetInfo.skipForwardControlKind)
        }
      }

      Task { [weak self] in
        guard let self else { return }

        for await interval in userSettings.$skipBackwardInterval.stream() {
          let intInterval = Int(interval)
          Self.log.debug("Skip backward interval changed to \(intInterval), reloading control")
          widgetState.skipBackwardInterval = intInterval
          reloadWidgets(kinds: [WidgetInfo.nowPlayingKind])
          controlCenter.reloadControls(ofKind: WidgetInfo.skipBackwardControlKind)
        }
      }
    }
  }

  // MARK: - Now Playing Snapshot

  // Now-playing artwork: largest view is 80pt (systemMedium) at 3x = 240px.
  private let maxNowPlayingArtworkPixels: CGFloat = 240

  private func writeNowPlayingSnapshot() async {
    let nowPlaying: NowPlayingSnapshot.NowPlaying? =
      if let onDeck = sharedState.onDeck {
        NowPlayingSnapshot.NowPlaying(
          episodeID: onDeck.id.rawValue,
          episodeTitle: onDeck.title,
          podcastTitle: onDeck.podcastTitle,
          pubDateTimestamp: onDeck.pubDate.timeIntervalSince1970,
          durationSeconds: onDeck.duration.seconds,
          artworkBase64: Self.encodeArtwork(onDeck.artwork, maxPixels: maxNowPlayingArtworkPixels)
        )
      } else {
        nil
      }

    let snapshot = NowPlayingSnapshot(
      schemaVersion: NowPlayingSnapshot.currentSchemaVersion,
      nowPlaying: nowPlaying,
      updatedAt: Date()
    )

    do {
      let data = try JSONEncoder().encode(snapshot)
      try await fileManager.writeData(data, to: WidgetInfo.nowPlayingSnapshotURL)
      Self.log.debug("Wrote now-playing snapshot (\(data.count) bytes)")
    } catch {
      Self.log.caughtError("writeNowPlayingSnapshot: failed to encode/write", error)
    }
  }

  // MARK: - Queue Snapshot

  // Queue artwork: ~28pt thumbnails at 3x = ~96px (rounded up for safety).
  private let maxQueueArtworkPixels: CGFloat = 96

  private func writeQueueSnapshot() async {
    let episodes = Array(queueWidgetEpisodes().prefix(5))
    let showPodcastImage = userSettings.alwaysShowPodcastImageInUpNext

    // Collect unique artwork URLs to avoid fetching the same image multiple times.
    var urlsByIndex: [Int: String] = [:]
    var uniqueURLs = Set<String>()
    for (index, episode) in episodes.enumerated() {
      let imageURL = (showPodcastImage ? episode.podcastImage : episode.image).absoluteString
      urlsByIndex[index] = imageURL
      uniqueURLs.insert(imageURL)
    }

    var artworkDict = [String: String](minimumCapacity: uniqueURLs.count)
    await withTaskGroup(of: (String, String?).self) { group in
      for urlString in uniqueURLs {
        group.addTask { [imagePipeline, maxQueueArtworkPixels] in
          guard let url = URL(string: urlString) else { return (urlString, nil) }
          do {
            let image = try await imagePipeline.image(for: url)
            let encoded = Self.encodeArtwork(image, maxPixels: maxQueueArtworkPixels)
            return (urlString, encoded)
          } catch {
            Self.log.caughtError(
              "writeQueueSnapshot: failed to load \(urlString)",
              error,
              level: { _ in .info }
            )
            return (urlString, nil)
          }
        }
      }
      for await (urlString, base64) in group {
        if let base64 {
          artworkDict[urlString] = base64
        }
      }
    }

    guard !Task.isCancelled else { return }

    let queueItems = episodes.enumerated()
      .map { index, episode in
        QueueSnapshot.QueueItem(
          episodeID: episode.id.rawValue,
          episodeTitle: episode.title,
          pubDateTimestamp: episode.pubDate.timeIntervalSince1970,
          durationSeconds: episode.duration.seconds,
          artworkURL: urlsByIndex[index]
        )
      }

    let snapshot = QueueSnapshot(
      schemaVersion: QueueSnapshot.currentSchemaVersion,
      queue: queueItems,
      queueTotalCount: queueWidgetEpisodes().count,
      artwork: artworkDict,
      updatedAt: Date()
    )

    do {
      let data = try JSONEncoder().encode(snapshot)
      try await fileManager.writeData(data, to: WidgetInfo.queueSnapshotURL)
      Self.log.debug("Wrote queue snapshot (\(data.count) bytes)")
    } catch {
      Self.log.caughtError("writeQueueSnapshot: failed to encode/write", error)
    }
  }

  // MARK: - Artwork Encoding

  private static func encodeArtwork(_ image: UIImage?, maxPixels: CGFloat) -> String? {
    guard let image else { return nil }
    let downsized = downsample(image, maxPixels: maxPixels)
    guard let jpegData = downsized.jpegData(compressionQuality: 0.8) else { return nil }
    return jpegData.base64EncodedString()
  }

  private static func downsample(_ image: UIImage, maxPixels: CGFloat) -> UIImage {
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
    let widgetCenter = widgetCenter
    widgetCenter.getCurrentConfigurations { result in
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
        widgetCenter.reloadTimelines(ofKind: kind)
      }
    }
  }
}
