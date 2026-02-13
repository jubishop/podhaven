// Copyright Justin Bishop, 2025

import FactoryKit
import Foundation
import Logging
import SwiftUI

extension Container {
  var fileLogManager: Factory<FileLogManager> {
    Factory(self) { FileLogManager() }.scope(.cached)
  }
}

struct FileLogManager: Sendable {
  static let logFileURL: URL = {
    AppInfo.documentsDirectory.appendingPathComponent("log.ndjson")
  }()

  private let maxFileSizeBytes = 2_000_000  // 2MB trigger
  private let targetFileSizeBytes = 1_750_000  // 1.75MB after truncation

  private let logQueue = DispatchQueue(label: "FileLogHandler", qos: .background)
  private let isActive = ThreadSafe(true)

  private static let log = Log.as("FileLogManager")

  // MARK: - Initialization

  fileprivate init() {}

  // MARK: - Logging

  func writeToFile(level: Logger.Level, entry: NDJSONLogEntry) {
    let runSynchronously = level == .critical || !isActive()

    if runSynchronously {
      let result = logQueue.sync { performWrite(entry) }
      Self.log.logResult(result)
    } else {
      logQueue.async {
        let result = performWrite(entry)
        Task(priority: .background) {
          Self.log.logResult(result)
        }
      }
    }
  }

  // MARK: - Scene Phase

  func handleScenePhaseChange(to scenePhase: ScenePhase) {
    switch scenePhase {
    case .active:
      isActive(true)
    case .background:
      isActive(false)
      logQueue.sync {}
    default:
      break
    }
  }

  // MARK: - File Operations

  private func performWrite(_ entry: NDJSONLogEntry) -> LogResult {
    do {
      let currentSize = try NDJSONFileWriter.appendEntry(entry, to: Self.logFileURL)

      if currentSize > UInt64(maxFileSizeBytes) {
        if let result = try NDJSONFileWriter.truncateIfNeeded(
          at: Self.logFileURL,
          maxSize: maxFileSizeBytes,
          targetSize: targetFileSizeBytes
        ) {
          return .log(
            .info,
            "File log truncated from \(result.originalSize) bytes to \(result.newSize) bytes"
          )
        }
      }

      return .success
    } catch {
      return .failure(error)
    }
  }
}
