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
      }
    }
  }
}

#if DEBUG
#Preview {
  DebugSection().preview()
}
#endif
