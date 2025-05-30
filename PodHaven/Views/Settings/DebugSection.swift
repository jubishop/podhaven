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
        Text("This is Jubi's phone")
      } else {
        Text("This is NOT Jubi's phone ")
      }

      #if DEBUG
      Text("in DEBUG")
      #else
      Text("in PRODUCTION")
      #endif
    }
  }
}

#if DEBUG
#Preview {
  DebugSection().preview()
}
#endif
