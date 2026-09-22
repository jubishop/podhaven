// Copyright Justin Bishop, 2025

import SwiftUI

struct SettingsRow<Content: View>: View {
  let infoText: String
  var alignment: VerticalAlignment = .top
  @ViewBuilder let content: () -> Content

  @State private var showPopover = false
  @State private var measuredHeight: CGFloat = 0

  var body: some View {
    GeometryReader { geometry in
      HStack(alignment: alignment, spacing: 16) {
        content()
        AppIcon.aboutInfo
          .imageButton {
            showPopover.toggle()
          }
          .accessibilityLabel("More Info")
          .buttonStyle(.plain)  // Necessary to keep hit target from bleeding out of row
          .popover(isPresented: $showPopover) {
            ViewThatFits(in: .vertical) {
              helpText
              ScrollView { helpText }
                .scrollBounceBehavior(.basedOnSize)
            }
            .frame(idealWidth: geometry.size.width * 0.75)
            .multilineTextAlignment(.leading)
            .padding()
            .presentationCompactAdaptation(.popover)
          }
      }
      .frame(width: geometry.size.width, alignment: .leading)
      .background {
        GeometryReader { heightGeometry in
          Color.clear
            .onChange(of: heightGeometry.size.height, initial: true) { _, newHeight in
              measuredHeight = newHeight
            }
        }
      }
    }
    .frame(height: measuredHeight > 0 ? measuredHeight : nil)
    .fixedSize(horizontal: false, vertical: measuredHeight == 0)
  }

  private var helpText: some View {
    Text(infoText)
      .fixedSize(horizontal: false, vertical: true)
  }
}

#if DEBUG
#Preview("Silence help at large text sizes") {
  VStack {
    SettingsRow(infoText: SilenceSettingsHelp.text) { Text("Shorten Silence") }
    SettingsRow(infoText: QuietAudioProtectionHelp.text) { Text("Quiet Audio Protection") }
    Spacer()
  }
  .padding()
  .frame(width: 320)
  .environment(\.dynamicTypeSize, .accessibility5)
}
#endif
