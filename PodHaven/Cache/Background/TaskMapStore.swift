// Copyright Justin Bishop, 2025

import FactoryKit
import Foundation
import Logging

// MARK: - TaskMapStore

/// Persists a mapping between URLSessionTask identifiers and the episode they belong to.
/// This allows the app to recover in-flight tasks after relaunch and correlate
/// delegate callbacks to domain entities.
actor TaskMapStore {
  private static let log = Log.as("TaskMapStore")

  private var byTaskID: [Int: MediaGUID] = [:]
  private var byKey: [MediaGUID: Int] = [:]

  private let fileURL: URL

  init() {
    // Store under Application Support
    let dir = AppInfo.applicationSupportDirectory.appendingPathComponent("background-downloads")
    do {
      try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    } catch {
      Self.log.error(error)
    }
    fileURL = dir.appendingPathComponent("taskmap.json")

    do {
      guard FileManager.default.fileExists(atPath: fileURL.path) else { return }
      let data = try Data(contentsOf: fileURL)
      let decoded = try JSONDecoder().decode([Int: MediaGUID].self, from: data)
      byTaskID = decoded
      byKey = Dictionary(uniqueKeysWithValues: decoded.map { ($0.value, $0.key) })
    } catch {
      Self.log.error(error)
    }
  }

  // MARK: - Public API

  func set(taskID: Int, for key: MediaGUID) {
    byTaskID[taskID] = key
    byKey[key] = taskID
    persist()
  }

  func taskID(for key: MediaGUID) -> Int? {
    byKey[key]
  }

  func key(for taskID: Int) -> MediaGUID? {
    byTaskID[taskID]
  }

  func remove(taskID: Int) {
    if let key = byTaskID.removeValue(forKey: taskID) {
      byKey.removeValue(forKey: key)
      persist()
    }
  }

  // MARK: - Persistence

  private func persist() {
    do {
      let data = try JSONEncoder().encode(byTaskID)
      try data.write(to: fileURL, options: .atomic)
    } catch {
      Self.log.error(error)
    }
  }
}

// MARK: - DI

extension Container {
  var cacheTaskMapStore: Factory<TaskMapStore> {
    Factory(self) { TaskMapStore() }.scope(.cached)
  }
}
