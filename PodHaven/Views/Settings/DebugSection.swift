// Copyright Justin Bishop, 2025

import BackgroundTasks
import FactoryKit
import GRDB
import Logging
import SwiftUI

struct DebugSection: View {
  @DynamicInjected(\.alert) private var alert

  var body: some View {
    Section("Debugging") {
      Text("Environment: \(AppInfo.environment.rawValue)")

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

      if AppInfo.myDevice {
        Button("Show Pending Background Tasks") {
          BGTaskScheduler.shared.getPendingTaskRequests { requests in
            let formatted = BackgroundTaskScheduler.formatPendingTasks(requests)
            Task { @MainActor in
              alert(
                title: "Pending Tasks",
                """
                Pending Background Tasks:
                  \(formatted)
                """
              )
            }
          }
        }
      }

      ShareLink(
        item: AppInfo.documentsDirectory.appendingPathComponent("log.ndjson"),
        preview: SharePreview(
          "PodHaven Logs",
          image: AppIcon.shareLogs.rawImage
        ),
        label: { AppIcon.shareLogs.label }
      )

      ShareLink(
        item: AppInfo.documentsDirectory.appendingPathComponent("db.sqlite"),
        preview: SharePreview(
          "PodHaven Database",
          image: AppIcon.shareDatabase.rawImage
        ),
        label: { AppIcon.shareDatabase.label }
      )
    }
  }
}

#if DEBUG
#Preview {
  DebugSection().preview()
}
#endif
