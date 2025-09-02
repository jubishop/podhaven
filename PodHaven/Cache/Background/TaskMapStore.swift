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
  private var isLoaded = false

  init() {
    // Store under Application Support
    let dir = AppInfo.applicationSupportDirectory.appendingPathComponent("background-downloads")
    fileURL = dir.appendingPathComponent("taskmap.json")
  }

  // MARK: - Public API

  func set(taskID: Int, for key: MediaGUID) async {
    await ensureLoaded()
    byTaskID[taskID] = key
    byKey[key] = taskID
    await persist()
  }

  func taskID(for key: MediaGUID) async -> Int? {
    await ensureLoaded()
    return byKey[key]
  }

  func key(for taskID: Int) async -> MediaGUID? {
    await ensureLoaded()
    return byTaskID[taskID]
  }

  func remove(taskID: Int) async {
    await ensureLoaded()
    if let key = byTaskID.removeValue(forKey: taskID) {
      byKey.removeValue(forKey: key)
      await persist()
    }
  }

  // MARK: - Persistence

  private func ensureLoaded() async {
    guard !isLoaded else { return }
    let fm: any FileManageable = Container.shared.podFileManager()

    // Ensure directory exists
    let dir = fileURL.deletingLastPathComponent()
    do { try await fm.createDirectory(at: dir, withIntermediateDirectories: true) } catch {}

    // Load if file exists
    if await fm.fileExists(at: fileURL) {
      do {
        let data = try await fm.readData(from: fileURL)
        let decoded = try JSONDecoder().decode([Int: MediaGUID].self, from: data)
        byTaskID = decoded
        byKey = Dictionary(uniqueKeysWithValues: decoded.map { ($0.value, $0.key) })
      } catch {
        Self.log.error(error)
      }
    }

    isLoaded = true
  }

  private func persist() async {
    let fm: any FileManageable = Container.shared.podFileManager()
    do {
      let data = try JSONEncoder().encode(byTaskID)
      try await fm.writeData(data, to: fileURL)
    } catch {
      Self.log.error(error)
    }
  }
}
extension Container {
  var cacheTaskMapStore: Factory<TaskMapStore> {
    Factory(self) { TaskMapStore() }.scope(.cached)
  }
}
