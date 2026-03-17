// Copyright Justin Bishop, 2026

import Foundation
import Logging
import UIKit

enum WidgetSnapshotReader {
  private static let log = Log.as(LogSubsystem.Widget.snapshotReader)

  // MARK: - Generic Reader

  static func read<T: WidgetSnapshotType>(_ type: T.Type, from url: URL) -> T? {
    guard FileManager.default.fileExists(atPath: url.path) else {
      log.warning("Snapshot file does not exist at \(url.path)")
      return nil
    }

    let data: Data
    do {
      data = try Data(contentsOf: url)
    } catch {
      log.caughtError("Failed to read snapshot file at \(url.path)", error)
      return nil
    }

    log.debug("Read snapshot file: \(data.count) bytes from \(url.lastPathComponent)")

    let snapshot: T
    do {
      snapshot = try JSONDecoder().decode(T.self, from: data)
    } catch {
      log.caughtError("Failed to decode snapshot at \(url.path)", error)
      return nil
    }

    guard snapshot.schemaVersion <= T.currentSchemaVersion else {
      log.warning(
        """
        Snapshot schema version \
        \(snapshot.schemaVersion) is newer than \
        supported \(T.currentSchemaVersion) for \(url.lastPathComponent)
        """
      )
      return nil
    }

    return snapshot
  }

  // MARK: - Convenience Readers

  static func readNowPlaying() -> NowPlayingSnapshot? {
    let snapshot = read(NowPlayingSnapshot.self, from: WidgetInfo.nowPlayingSnapshotURL)
    if let snapshot {
      log.debug(
        """
        Decoded now-playing snapshot: \
        nowPlaying=\(snapshot.nowPlaying != nil), \
        updatedAt=\(snapshot.updatedAt)
        """
      )
    }
    return snapshot
  }

  static func readQueue() -> QueueSnapshot? {
    let snapshot = read(QueueSnapshot.self, from: WidgetInfo.queueSnapshotURL)
    if let snapshot {
      log.debug(
        """
        Decoded queue snapshot: \
        queue=\(snapshot.queue.count) items, \
        updatedAt=\(snapshot.updatedAt)
        """
      )
    }
    return snapshot
  }

  static func readPodcastDetail() -> PodcastDetailSnapshot? {
    let snapshot = read(PodcastDetailSnapshot.self, from: WidgetInfo.podcastDetailSnapshotURL)
    if let snapshot {
      log.debug(
        """
        Decoded podcast-detail snapshot: \
        podcasts=\(snapshot.subscribedPodcasts.count), \
        updatedAt=\(snapshot.updatedAt)
        """
      )
    }
    return snapshot
  }

  // MARK: - Artwork

  static func decodeArtwork(from base64String: String?) -> UIImage? {
    guard let base64String else { return nil }

    guard let data = Data(base64Encoded: base64String) else {
      log.warning("Failed to decode base64 artwork string (\(base64String.count) chars)")
      return nil
    }

    guard let image = UIImage(data: data) else {
      log.warning("Failed to create UIImage from decoded artwork data (\(data.count) bytes)")
      return nil
    }

    return image
  }

  static func loadArtwork() -> [String: String] {
    let url = WidgetInfo.artworkURL
    guard FileManager.default.fileExists(atPath: url.path) else { return [:] }
    do {
      let data = try Data(contentsOf: url)
      let decoded = try JSONDecoder().decode(WidgetArtwork.self, from: data)
      log.debug("Loaded artwork file: \(decoded.artwork.count) entries")
      return decoded.artwork
    } catch {
      log.caughtError("Failed to load artwork file", error)
      return [:]
    }
  }

  static func decodeArtwork(forKey key: String?, from artworkDict: [String: String]) -> UIImage? {
    guard let key, let base64String = artworkDict[key] else { return nil }

    guard let data = Data(base64Encoded: base64String) else {
      log.warning("Failed to decode base64 artwork for key \(key) (\(base64String.count) chars)")
      return nil
    }

    guard let image = UIImage(data: data) else {
      log.warning("Failed to create UIImage from artwork data for key \(key) (\(data.count) bytes)")
      return nil
    }

    return image
  }
}
