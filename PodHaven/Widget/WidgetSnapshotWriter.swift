// Copyright Justin Bishop, 2026

import CoreMedia
import FactoryKit
import Foundation
import GRDB
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
  private var observatory: Observatory { Container.shared.observatory() }
  private var sharedState: SharedState { Container.shared.sharedState() }
  private var sleeper: any Sleepable { Container.shared.sleeper() }
  private var userSettings: UserSettings { Container.shared.userSettings() }
  private var widgetCenter: any WidgetReloading { Container.shared.widgetCenter() }
  private var widgetState: WidgetState { Container.shared.widgetState() }

  private static let log = Log.as(LogSubsystem.Widget.writer)

  private let nowPlayingDebounce = Debounce(duration: .milliseconds(250))
  private let queueDebounce = Debounce(duration: .seconds(1))
  private let podcastDetailDebounce = Debounce(duration: .seconds(30))
  private let artworkDebounce = Debounce(duration: .milliseconds(500))
  private let queueWidgetEpisodes = ThreadSafe<[WidgetEpisode]>([])
  private let podcastDetailData = ThreadSafe<[PodcastDetailWidgetData]>([])
  // Double-optional: .none = no value received yet, .some(nil) = received nil
  private let lastOnDeck = ThreadSafe<OnDeck??>(OnDeck??.none)
  private let lastPlaybackStatus = ThreadSafe<PlaybackStatus>(.stopped)
  private let heartbeatTask = ThreadSafe<Task<Void, Never>?>(nil)

  // All artwork at 240px max — the largest needed size (now-playing / podcast headers).
  // Smaller uses (queue thumbnails, episode rows) downscale at render time.
  private let maxArtworkPixels: CGFloat = 240

  // MARK: - Start

  func start() {
    guard Function.neverCalled() else { return }

    Task { [weak self] in
      guard let self else { return }

      for await onDeck in sharedState.$onDeck.stream() {
        let changed: Bool = lastOnDeck { last in
          defer { last = .some(onDeck) }
          guard let previous = last else { return true }
          guard let onDeck else { return previous != nil }
          guard let previous else { return true }
          return !onDeck.widgetEquals(previous)
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

      var retryDelay: Duration = .seconds(1)
      while !Task.isCancelled {
        do {
          for try await episodes in observatory.queueWidgetEpisodes() {
            retryDelay = .seconds(1)
            queueWidgetEpisodes(episodes)
            queueDebounce { [weak self] in
              guard let self else { return }
              await writeQueueSnapshot()
              reloadWidgets(kinds: [WidgetInfo.queueKind])
            }
          }
        } catch {
          Self.log.caughtError("start: queueWidgetEpisodes observation failed", error)
          try? await sleeper.sleep(for: retryDelay)
          retryDelay = min(retryDelay * 2, .seconds(60))
        }
      }
    }

    Task { [weak self] in
      guard let self else { return }

      var retryDelay: Duration = .seconds(1)
      var isFirstEmission = true
      while !Task.isCancelled {
        do {
          for try await data in observatory.podcastDetailWidgetData() {
            retryDelay = .seconds(1)
            podcastDetailData(data)
            await writePodcastEntityList()

            guard await isWidgetPlaced(kind: WidgetInfo.podcastDetailKind) else { continue }

            let isInitial = isFirstEmission
            isFirstEmission = false

            if isInitial {
              await writePodcastDetailSnapshot()
              scheduleArtworkReconciliation()
              reloadWidgets(kinds: [WidgetInfo.podcastDetailKind])
            } else {
              podcastDetailDebounce { [weak self] in
                guard let self else { return }
                await writePodcastDetailSnapshot()
                scheduleArtworkReconciliation()
                reloadWidgets(kinds: [WidgetInfo.podcastDetailKind])
              }
            }
          }
        } catch {
          Self.log.caughtError("start: podcastDetailWidgetData observation failed", error)
          try? await sleeper.sleep(for: retryDelay)
          retryDelay = min(retryDelay * 2, .seconds(60))
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

  // MARK: - Now Playing Snapshot

  // Now-playing artwork: largest view is 80pt (systemMedium) at 3x = 240px.
  private let maxNowPlayingArtworkPixels: CGFloat = 240

  private func writeNowPlayingSnapshot() async {
    let nowPlaying: NowPlayingSnapshot.NowPlaying? =
      if let onDeck = sharedState.onDeck {
        await NowPlayingSnapshot.NowPlaying(
          episodeID: onDeck.id.rawValue,
          episodeTitle: onDeck.title,
          podcastTitle: onDeck.podcastTitle,
          pubDateTimestamp: onDeck.pubDate.timeIntervalSince1970,
          durationSeconds: onDeck.duration.seconds,
          artworkBase64: Self.loadAndEncodeImage(
            from: onDeck.image,
            maxPixels: maxNowPlayingArtworkPixels,
            imagePipeline: imagePipeline
          )
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

    // Fetch each unique URL once.
    var artworkDict: [String: String] = [:]
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
              remarkable: .info
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

  // MARK: - Podcast Detail Snapshot

  private func writePodcastDetailSnapshot() async {
    let podcastData = podcastDetailData()

    let subscribedPodcasts = podcastData.map { item in
      PodcastDetailSnapshot.SubscribedPodcast(
        feedURLString: item.podcast.feedURL.rawValue.absoluteString,
        title: item.podcast.title,
        artworkURL: item.podcast.image.absoluteString,
        recentEpisodes: item.episodes.prefix(4)
          .map { episode in
            PodcastDetailSnapshot.PodcastEpisodeItem(
              episodeID: episode.id.rawValue,
              episodeTitle: episode.title,
              pubDateTimestamp: episode.pubDate.timeIntervalSince1970,
              durationSeconds: episode.duration.seconds,
              artworkURL: episode.episodeImage?.absoluteString
            )
          }
      )
    }

    let snapshot = PodcastDetailSnapshot(
      schemaVersion: PodcastDetailSnapshot.currentSchemaVersion,
      subscribedPodcasts: subscribedPodcasts,
      updatedAt: Date()
    )

    do {
      let data = try JSONEncoder().encode(snapshot)
      try await fileManager.writeData(data, to: WidgetInfo.podcastDetailSnapshotURL)
      Self.log.debug("Wrote podcast-detail snapshot (\(data.count) bytes)")
    } catch {
      Self.log.caughtError("writePodcastDetailSnapshot: failed to encode/write", error)
    }
  }

  // MARK: - Podcast Entity List

  private func writePodcastEntityList() async {
    let data = podcastDetailData()
    let items = data.map { item in
      PodcastEntityListSnapshot.PodcastEntityItem(
        feedURLString: item.podcast.feedURL.rawValue.absoluteString,
        title: item.podcast.title
      )
    }

    let snapshot = PodcastEntityListSnapshot(
      schemaVersion: PodcastEntityListSnapshot.currentSchemaVersion,
      podcasts: items,
      updatedAt: Date()
    )

    do {
      let encodedData = try JSONEncoder().encode(snapshot)
      try await fileManager.writeData(encodedData, to: WidgetInfo.podcastEntityListURL)
      Self.log.debug("Wrote podcast entity list (\(encodedData.count) bytes)")
    } catch {
      Self.log.caughtError("writePodcastEntityList: failed to encode/write", error)
    }
  }

  // MARK: - Shared Artwork

  private func scheduleArtworkReconciliation() {
    artworkDebounce { [weak self] in
      guard let self else { return }
      await reconcileArtwork()
    }
  }

  // Collects artwork URLs referenced by podcast detail data, fetches any that
  // are missing from the existing artwork file, and writes the file with
  // exactly the needed set — pruning stale entries automatically.
  // Now-playing and queue embed artwork directly in their snapshot files.
  private func reconcileArtwork() async {
    var neededURLs = Set<String>()

    for item in podcastDetailData() {
      neededURLs.insert(item.podcast.image.absoluteString)
      for episode in item.episodes.prefix(4) {
        if let episodeImage = episode.episodeImage {
          neededURLs.insert(episodeImage.absoluteString)
        }
      }
    }

    // Read existing artwork to avoid re-fetching images we already have.
    var existing: [String: String] = [:]
    do {
      let data = try await fileManager.readData(from: WidgetInfo.artworkURL)
      let decoded = try JSONDecoder().decode(WidgetArtwork.self, from: data)
      existing = decoded.artwork
    } catch {
      // File doesn't exist yet or is malformed — start fresh.
    }

    // Fetch only new URLs, keep existing entries that are still needed.
    var artworkDict: [String: String] = [:]
    var fetchedNewImages = false
    await withTaskGroup(of: (String, String?).self) { group in
      for urlString in neededURLs {
        if let cached = existing[urlString] {
          artworkDict[urlString] = cached
          continue
        }
        group.addTask { [imagePipeline, maxArtworkPixels] in
          guard let url = URL(string: urlString) else { return (urlString, nil) }
          do {
            let image = try await imagePipeline.image(for: url)
            let encoded = Self.encodeArtwork(image, maxPixels: maxArtworkPixels)
            return (urlString, encoded)
          } catch {
            Self.log.caughtError(
              "reconcileArtwork: failed to load \(urlString)",
              error,
              remarkable: .info
            )
            return (urlString, nil)
          }
        }
      }
      for await (urlString, base64) in group {
        if let base64 {
          artworkDict[urlString] = base64
          fetchedNewImages = true
        }
      }
    }

    guard !Task.isCancelled else { return }

    do {
      let encoded = try JSONEncoder().encode(WidgetArtwork(artwork: artworkDict))
      try await fileManager.writeData(encoded, to: WidgetInfo.artworkURL)
      Self.log.debug(
        "Wrote artwork file (\(artworkDict.count) entries, \(encoded.count) bytes)"
      )
    } catch {
      Self.log.caughtError("reconcileArtwork: failed to write artwork file", error)
      return
    }

    // If new images were fetched, reload widgets so they pick up the artwork.
    if fetchedNewImages {
      Self.log.debug("New artwork fetched, reloading podcast detail timeline")
      reloadWidgets(kinds: [WidgetInfo.podcastDetailKind])
    }
  }

  // MARK: - Artwork Encoding

  private static func loadAndEncodeImage(
    from url: URL,
    maxPixels: CGFloat,
    imagePipeline: ImagePipeline
  ) async -> String? {
    do {
      let image = try await imagePipeline.image(for: url)
      return encodeArtwork(image, maxPixels: maxPixels)
    } catch {
      log.caughtError(
        "loadAndEncodeImage: failed to load \(url)",
        error,
        remarkable: .info
      )
      return nil
    }
  }

  private static func encodeArtwork(_ image: UIImage, maxPixels: CGFloat) -> String? {
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

  // MARK: - Widget Placement

  private func isWidgetPlaced(kind: String) async -> Bool {
    await withCheckedContinuation { continuation in
      widgetCenter.getCurrentConfigurations { result in
        switch result {
        case .success(let configurations):
          continuation.resume(returning: configurations.contains { $0.kind == kind })
        case .failure(let error):
          Self.log.caughtError("isWidgetPlaced: failed to get configurations", error)
          continuation.resume(returning: true)
        }
      }
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
