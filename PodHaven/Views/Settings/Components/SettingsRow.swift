// Copyright Justin Bishop, 2025

import SwiftUI

struct SettingsRow<Content: View>: View {
  let infoText: String
  @ViewBuilder let content: () -> Content

  @State private var showPopover = false

  var body: some View {
    HStack(alignment: .top, spacing: 16) {
      content()
      AppIcon.aboutInfo
        .imageButton {
          showPopover.toggle()
        }
        .buttonStyle(.plain)  // Necessary to keep hit target from bleeding out of row
        .popover(isPresented: $showPopover) {
          Text(infoText)
            .multilineTextAlignment(.leading)
            .padding()
            .presentationCompactAdaptation(.popover)
        }
    }
  }
}
