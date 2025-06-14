// Copyright Justin Bishop, 2025

import FactoryKit
import SwiftUI

struct DebugSection: View {
  @DynamicInjected(\.alert) private var alert
  @DynamicInjected(\.playManager) private var playManager

  var body: some View {
    Section("Debugging") {
      Text("Environment: \(AppInfo.environment)")

      Text("Device ID: \(AppInfo.deviceIdentifier)")

      if AppInfo.myPhone {
        Text("Jubi's phone")
      } else {
        Text("NOT Jubi's phone ")
      }

      #if DEBUG
      Text("in DEBUG")
      #else
      Text("in PRODUCTION")
      #endif

      Text("Version \(AppInfo.version) (\(AppInfo.buildNumber))")

      Text("Built \(Date.usShortDateFormat.string(from: AppInfo.buildDate))")

      ShareLink(
        item: FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!
          .appendingPathComponent("db.sqlite")
      ) {
        Label("Share Database", systemImage: "square.and.arrow.up")
      }
    }
  }
}

#if DEBUG
#Preview {
  DebugSection().preview()
}
#endif
