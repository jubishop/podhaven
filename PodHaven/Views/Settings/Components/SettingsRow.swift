// Copyright Justin Bishop, 2025

import SwiftUI

struct SettingsRow<Content: View>: View {
  let infoText: String
  @ViewBuilder let content: () -> Content

  @State private var showPopover = false

  var body: some View {
    GeometryReader { geometry in
      HStack(spacing: 16) {
        content()
        AppIcon.aboutInfo
          .imageButton {
            showPopover.toggle()
          }
          .buttonStyle(.plain)  // Necessary to keep hit target from bleeding out of row
          .popover(isPresented: $showPopover) {
            Text(infoText)
              .frame(idealWidth: geometry.size.width * 0.75)
              .multilineTextAlignment(.leading)
              .padding()
              .presentationCompactAdaptation(.popover)
          }
      }
    }
  }
}
