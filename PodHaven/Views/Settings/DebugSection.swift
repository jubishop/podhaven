// Copyright Justin Bishop, 2025

import FactoryKit
import GRDB
import Logging
import SwiftUI

struct DebugSection: View {
  @DynamicInjected(\.alert) private var alert
  @DynamicInjected(\.bgTaskScheduler) private var bgTaskScheduler

  var body: some View {
    Section("Debugging") {
      Text("Environment: \(AppInfo.environment.rawValue)")

      if AppInfo.myDevice {
        Button("Copy Device ID") {
          UIPasteboard.general.string = AppInfo.deviceIdentifier
        }

        Text("Git: \(AppInfo.gitCommitHash)")
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
          bgTaskScheduler.getPendingTaskRequests { requests in
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
        item: AppInfo.logFileURL,
        preview: SharePreview(
          "PodHaven Logs",
          image: AppIcon.shareLogs.rawImage
        ),
        label: { AppIcon.shareLogs.label }
      )

      ShareLink(
        item: WidgetInfo.logFileURL,
        preview: SharePreview(
          "Widget Logs",
          image: AppIcon.shareLogs.rawImage
        ),
        label: { AppIcon.shareLogs.label("Share Widget Logs") }
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
