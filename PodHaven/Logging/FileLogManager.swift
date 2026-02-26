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

  private static let log = Log.as("FileLogManager")

  private let writer: NDJSONLogFileManager
  private let isActive = ThreadSafe(true)

  // MARK: - Initialization

  fileprivate init() {
    self.writer = NDJSONLogFileManager(
      fileURL: Self.logFileURL,
      maxFileSizeBytes: 2_000_000,
      targetFileSizeBytes: 1_750_000,
      queueLabel: "FileLogHandler",
      onError: { error in
        Task(priority: .background) {
          Self.log.error(error)
        }
      },
      onTruncation: { originalSize, newSize in
        Task(priority: .background) {
          Self.log.info("File log truncated from \(originalSize) bytes to \(newSize) bytes")
        }
      }
    )
  }

  // MARK: - Logging

  func writeToFile(level: Logger.Level, entry: NDJSONLogEntry) {
    let runSynchronously = level == .critical || !isActive()

    if runSynchronously {
      do {
        if let truncation = try writer.writeSync(entry) {
          Self.log.info(
            "File log truncated from \(truncation.originalSize) bytes to \(truncation.newSize) bytes"
          )
        }
      } catch {
        Self.log.error(error)
      }
    } else {
      writer.writeAsync(entry)
    }
  }

  // MARK: - Scene Phase

  func handleScenePhaseChange(to scenePhase: ScenePhase) {
    switch scenePhase {
    case .active:
      isActive(true)
    case .background:
      isActive(false)
      writer.flush()
    default:
      break
    }
  }
}
