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
  private enum QueueArtworkSource {
    case persistedSnapshot
    case remote
  }

  private var controlCenter: any ControlReloading { Container.shared.controlCenter() }
  private var fileManager: any FileManaging { Container.shared.fileManager() }
  private var imagePipeline: ImagePipeline { Container.shared.imagePipeline() }
  private var observatory: any Observing { Container.shared.observatory() }
  private var sharedState: SharedState { Container.shared.sharedState() }
  private var sleeper: any Sleepable { Container.shared.sleeper() }
  private var taskPriority: @Sendable (TaskPriority?) -> TaskPriority? {
    Container.shared.taskPriority()
  }
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
      let onDeckStream = sharedState.$onDeck.stream()
      let currentEpisodeIDStream = sharedState.$currentEpisodeID.stream()
      let playbackStatusStream = sharedState.$playbackStatus.stream()
      let queueStream = sharedState.$queuedPodcastEpisodes.stream()
      let queueImageSettingStream = userSettings.$alwaysShowPodcastImageInUpNext.stream()
      let skipForwardIntervalStream = userSettings.$skipForwardInterval.stream()
      let skipBackwardIntervalStream = userSettings.$skipBackwardInterval.stream()

      let startupTask = Task(priority: taskPriority(.utility)) { [weak self] in
        guard let self else { return }
        await prepareForStartup()
      }

      Task(priority: taskPriority(.utility)) { [weak self] in
        await startupTask.value
        guard let self else { return }

        for await onDeck in onDeckStream.dropFirst() {
          let changed: Bool = lastOnDeck { last in
            defer { last = onDeck }
            guard let onDeck else { return last != nil }
            guard let last else { return true }
            return !onDeck.widgetEquals(last)
          }
          if changed {
            scheduleNowPlayingSnapshotWrite()
          }
        }
      }

      Task(priority: taskPriority(.utility)) { [weak self] in
        await startupTask.value
        guard let self else { return }

        for await currentEpisodeID in currentEpisodeIDStream.dropFirst()
        where currentEpisodeID == nil && sharedState.onDeck == nil {
          scheduleNowPlayingSnapshotWrite()
        }
      }

      Task(priority: taskPriority(.utility)) { [weak self] in
        await startupTask.value
        guard let self else { return }

        for await status in playbackStatusStream.dropFirst() {
          let changed: Bool = lastPlaybackStatus { last in
            defer { last = status }
            return status != last
          }
          guard changed else { continue }
          widgetState.playbackStatus = status
          Self.log.debug("Playback status changed to \(status), reloading play/pause control")
          reloadWidgets(kinds: [
            WidgetInfo.nowPlayingKind,
            WidgetInfo.lockScreenNowPlayingKind,
            WidgetInfo.nowPlayingQueueKind,
          ])
          controlCenter.reloadControls(ofKind: WidgetInfo.playPauseControlKind)

          if status.playing {
            startHeartbeat()
          } else {
            stopHeartbeat()
          }
        }
      }

      Task(priority: taskPriority(.utility)) { [weak self] in
        await startupTask.value
        guard let self else { return }

        for await podcastEpisodes in queueStream.dropFirst() {
          let episodes = podcastEpisodes.map(WidgetEpisode.init)
          let changed: Bool = queueWidgetEpisodes { current in
            defer { current = episodes }
            return current != episodes
          }
          guard changed else { continue }
          queueDebounce { [weak self] in
            guard let self else { return }
            await writeQueueSnapshot()
            reloadWidgets(kinds: [WidgetInfo.queueKind, WidgetInfo.nowPlayingQueueKind])
          }
        }
      }

      Task(priority: taskPriority(.utility)) { [weak self] in
        await startupTask.value
        guard let self else { return }

        for await _ in queueImageSettingStream.dropFirst() {
          queueDebounce { [weak self] in
            guard let self else { return }
            await writeQueueSnapshot()
            reloadWidgets(kinds: [WidgetInfo.queueKind, WidgetInfo.nowPlayingQueueKind])
          }
        }
      }

      Task(priority: taskPriority(.utility)) { [weak self] in
        await startupTask.value
        guard let self else { return }

        for await interval in skipForwardIntervalStream.dropFirst() {
          let intInterval = Int(interval)
          Self.log.debug("Skip forward interval changed to \(intInterval), reloading control")
          widgetState.skipForwardInterval = intInterval
          reloadWidgets(kinds: [WidgetInfo.nowPlayingKind, WidgetInfo.nowPlayingQueueKind])
          controlCenter.reloadControls(ofKind: WidgetInfo.skipForwardControlKind)
        }
      }

      Task(priority: taskPriority(.utility)) { [weak self] in
        await startupTask.value
        guard let self else { return }

        for await interval in skipBackwardIntervalStream.dropFirst() {
          let intInterval = Int(interval)
          Self.log.debug("Skip backward interval changed to \(intInterval), reloading control")
          widgetState.skipBackwardInterval = intInterval
          reloadWidgets(kinds: [WidgetInfo.nowPlayingKind, WidgetInfo.nowPlayingQueueKind])
          controlCenter.reloadControls(ofKind: WidgetInfo.skipBackwardControlKind)
        }
      }
    }
  }

  private func prepareForStartup() async {
    let currentBuild = AppInfo.buildNumber
    let previousRecoveryBuild = widgetState.lastUpgradeRecoveryBuild
    let onDeck = sharedState.onDeck
    let playbackStatus = sharedState.playbackStatus
    let queuedEpisodes: [WidgetEpisode]
    do {
      queuedEpisodes = try await observatory.queuedPodcastEpisodes().get().map(WidgetEpisode.init)
    } catch {
      Self.log.caughtError("Failed to read the queue before widget startup", error)
      return
    }

    lastOnDeck(onDeck)
    lastPlaybackStatus(playbackStatus)
    queueWidgetEpisodes(queuedEpisodes)

    widgetState.playbackStatus = playbackStatus
    widgetState.skipForwardInterval = Int(userSettings.skipForwardInterval)
    widgetState.skipBackwardInterval = Int(userSettings.skipBackwardInterval)

    controlCenter.reloadControls(ofKind: WidgetInfo.playPauseControlKind)
    controlCenter.reloadControls(ofKind: WidgetInfo.skipForwardControlKind)
    controlCenter.reloadControls(ofKind: WidgetInfo.skipBackwardControlKind)

    if playbackStatus.playing {
      startHeartbeat()
    } else {
      stopHeartbeat()
    }

    let nowPlayingSnapshotReady: Bool
    if onDeck == nil && sharedState.currentEpisodeID != nil {
      nowPlayingSnapshotReady = fileManager.fileExists(at: WidgetInfo.nowPlayingSnapshotURL)
      Self.log.debug(
        "Preserving the existing now-playing snapshot while the persisted episode restores"
      )
    } else {
      nowPlayingSnapshotReady = await writeNowPlayingSnapshot()
    }
    let queueSnapshotReady = await writeQueueSnapshot(artworkSource: .persistedSnapshot)

    guard nowPlayingSnapshotReady && queueSnapshotReady else {
      Self.log.error(
        """
        Widget startup snapshots incomplete for build \(currentBuild): \
        nowPlayingReady=\(nowPlayingSnapshotReady), queueReady=\(queueSnapshotReady); \
        skipping timeline reload
        """
      )
      return
    }

    let extensionAcknowledgment: String
    do {
      if let acknowledgment = try WidgetInfo.readExtensionAcknowledgment() {
        let latestTimelineRequestAt: String
        if let timestamp = acknowledgment.latestTimelineRequestAt {
          latestTimelineRequestAt = "\(timestamp)"
        } else {
          latestTimelineRequestAt = "none"
        }
        extensionAcknowledgment =
          "build=\(acknowledgment.buildNumber), initializedAt=\(acknowledgment.initializedAt), "
          + "latestTimelineRequestAt=\(latestTimelineRequestAt)"
      } else {
        extensionAcknowledgment = "none"
      }
    } catch {
      Self.log.caughtError(
        "Failed to read the widget extension acknowledgment before startup reload",
        error
      )
      extensionAcknowledgment = "unreadable"
    }

    if previousRecoveryBuild == currentBuild {
      Self.log.debug(
        """
        Widget startup ready for build \(currentBuild): previousRecoveryBuild=\(currentBuild), \
        priorExtensionAcknowledgment=\(extensionAcknowledgment); requesting one coalesced \
        targeted reload for \(WidgetInfo.timelineKinds.count) timeline kinds
        """
      )
      reloadWidgets(kinds: WidgetInfo.timelineKinds)
      widgetState.lastUpgradeRecoveryBuild = currentBuild
    } else {
      let previousBuild = previousRecoveryBuild ?? "none"
      Self.log.info(
        """
        Recovering widget timelines after build transition \
        \(previousBuild) -> \(currentBuild): initialSnapshotsReady=true, \
        priorExtensionAcknowledgment=\(extensionAcknowledgment); requesting reload-all
        """
      )
      widgetCenter.reloadAllTimelines()
      widgetState.lastUpgradeRecoveryBuild = currentBuild
      Self.log.info("Widget upgrade recovery completed for build \(currentBuild)")
    }
  }

  // MARK: - Now Playing Snapshot

  // Now-playing artwork: largest view is 80pt (systemMedium) at 3x = 240px.
  private let maxNowPlayingArtworkPixels: CGFloat = 240

  private func scheduleNowPlayingSnapshotWrite() {
    nowPlayingDebounce { [weak self] in
      guard let self else { return }
      await writeNowPlayingSnapshot()
      reloadWidgets(kinds: [
        WidgetInfo.nowPlayingKind,
        WidgetInfo.lockScreenNowPlayingKind,
        WidgetInfo.nowPlayingQueueKind,
      ])
    }
  }

  @discardableResult
  private func writeNowPlayingSnapshot() async -> Bool {
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
      return true
    } catch {
      Self.log.caughtError("writeNowPlayingSnapshot: failed to encode/write", error)
      return false
    }
  }

  // MARK: - Queue Snapshot

  // Queue artwork: ~28pt thumbnails at 3x = ~96px (rounded up for safety).
  private let maxQueueArtworkPixels: CGFloat = 96

  @discardableResult
  private func writeQueueSnapshot(artworkSource: QueueArtworkSource = .remote) async -> Bool {
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
    switch artworkSource {
    case .persistedSnapshot:
      if fileManager.fileExists(at: WidgetInfo.queueSnapshotURL) {
        do {
          let data = try await fileManager.readData(from: WidgetInfo.queueSnapshotURL)
          let snapshot = try JSONDecoder().decode(QueueSnapshot.self, from: data)
          artworkDict = snapshot.artwork.filter { uniqueURLs.contains($0.key) }
        } catch {
          Self.log.caughtError(
            "writeQueueSnapshot: failed to reuse persisted artwork",
            error,
            level: .info
          )
        }
      }
    case .remote:
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
                level: .info
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
    }

    guard !Task.isCancelled else { return false }

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
      return true
    } catch {
      Self.log.caughtError("writeQueueSnapshot: failed to encode/write", error)
      return false
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

  // Reload the now-playing timelines periodically while playing so each
  // widget's fallback "paused" entry keeps getting pushed forward. These
  // reloads are free while the app holds an active audio session.
  private func startHeartbeat() {
    stopHeartbeat()
    let task = Task(priority: taskPriority(.utility)) { [weak self] in
      while !Task.isCancelled {
        guard let self else { return }
        try? await sleeper.sleep(for: .seconds(240))
        guard !Task.isCancelled else { return }
        reloadWidgets(kinds: [WidgetInfo.nowPlayingKind, WidgetInfo.nowPlayingQueueKind])
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
    widgetCenter.placedWidgetKinds { result in
      let placedKinds: Set<String>
      switch result {
      case .success(let value):
        placedKinds = value
      case .failure(let error):
        Self.log.caughtError("reloadWidgets: failed to get current widget configurations", error)
        return
      }

      for kind in kinds where placedKinds.contains(kind) {
        Self.log.debug("Reloading timeline for \(kind)")
        widgetCenter.reloadTimelines(ofKind: kind)
      }
    }
  }
}
