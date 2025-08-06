// Copyright Justin Bishop, 2025

import FactoryKit
import GRDB
import SwiftUI

struct DebugSection: View {
  @DynamicInjected(\.alert) private var alert
  @DynamicInjected(\.fileLogManager) private var fileLogManager
  @DynamicInjected(\.playManager) private var playManager
  @DynamicInjected(\.refreshManager) private var refreshManager
  @DynamicInjected(\.repo) private var repo

  var body: some View {
    Section("Debugging") {
      Text("Environment: \(AppInfo.environment)")

      Text("Device ID: \(AppInfo.deviceIdentifier)")

      #if DEBUG
      Text("in DEBUG")
      #else
      Text("Version \(AppInfo.version) (\(AppInfo.buildNumber))")
      Text("Built \(Date.usShortDateFormatWithTime.string(from: AppInfo.buildDate))")
      #endif

      ShareLink(
        item: FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!
          .appendingPathComponent("log.ndjson")
      ) {
        Label("Share Logs", systemImage: "square.and.arrow.up")
      }

      ShareLink(
        item: FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!
          .appendingPathComponent("db.sqlite")
      ) {
        Label("Share Database", systemImage: "square.and.arrow.up")
      }

      if AppInfo.myDevice {
        Button("Truncate Log File") {
          Task { try await fileLogManager.truncateLogFile() }
        }

        Button("Refresh Podcasts") {
          Task { try await refreshManager.performRefresh(stalenessThreshold: Date()) }
        }

        Button("Delete All Cached Files", role: .destructive) {
          Task { await deleteAllCachedFiles() }
        }
      }
    }
  }

  // MARK: - Private Methods

  private func deleteAllCachedFiles() async {
    do {
      // Delete the episodes/ folder
      let applicationSupportDirectory = FileManager.default
        .urls(for: .applicationSupportDirectory, in: .userDomainMask)
        .first

      guard let applicationSupportDirectory
      else {
        alert("Could not find application support directory")
        return
      }
      let episodesCacheDirectory = applicationSupportDirectory.appendingPathComponent("episodes")

      if FileManager.default.fileExists(atPath: episodesCacheDirectory.path) {
        try FileManager.default.removeItem(at: episodesCacheDirectory)
      }

      // Clear all cached filenames in the database
      _ = try await AppDB.onDisk.db.write { db in
        try Episode.updateAll(db, Episode.Columns.cachedFilename.set(to: nil))
      }

      alert("All cached files deleted successfully")
    } catch {
      alert(ErrorKit.message(for: error))
    }
  }
}

#if DEBUG
#Preview {
  DebugSection().preview()
}
#endif
