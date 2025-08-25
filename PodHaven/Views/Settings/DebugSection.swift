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

      Text("Language: \(AppInfo.languageCode ?? "Unknown")")

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
        AppLabel.shareLogs.label
      }

      ShareLink(
        item: FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!
          .appendingPathComponent("db.sqlite")
      ) {
        AppLabel.shareDatabase.label
      }
    }
  }
}

#if DEBUG
#Preview {
  DebugSection().preview()
}
#endif
