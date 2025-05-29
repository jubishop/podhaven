// Copyright Justin Bishop, 2025

import FactoryKit
import SwiftUI

struct DebugSection: View {
  @DynamicInjected(\.alert) private var alert

  private var playManager: PlayManager { get async { await Container.shared.playManager() } }

  var body: some View {
    Section("Debugging") {
      Text("Environment: \(AppInfo.environment)")

      Text("Device ID: \(AppInfo.deviceIdentifier)")

      if AppInfo.myPhone {
        Text("This is my phone")
      }

      #if DEBUG
      Text("in DEBUG")
      #else
      Text("NOT in DEBUG")
      #endif
    }
  }
}

#if DEBUG
#Preview {
  DebugSection().preview()
}
#endif
