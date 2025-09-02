// Copyright Justin Bishop, 2025

import FactoryKit
import GRDB
import SwiftUI

struct DebugSection: View {
  var body: some View {
    Section("Debugging") {
      Text("Environment: \(AppInfo.environment)")

      Text("Device ID: \(AppInfo.deviceIdentifier)")

      if AppInfo.myDevice {
        Text("My Device")
      }

      Text("Language: \(AppInfo.languageCode ?? "Unknown")")

      #if DEBUG
      Text("in DEBUG")
      #else
      Text("Version \(AppInfo.version) (\(AppInfo.buildNumber))")
      Text("Built \(Date.usShortDateFormatWithTime.string(from: AppInfo.buildDate))")
      #endif

      ShareLink(
        item: AppInfo.documentsDirectory.appendingPathComponent("log.ndjson")
      ) {
        AppLabel.shareLogs.label
      }

      ShareLink(
        item: AppInfo.documentsDirectory.appendingPathComponent("db.sqlite")
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
