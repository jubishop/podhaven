// Copyright Justin Bishop, 2026

import SwiftUI

enum QuietAudioProtectionHelp {
  static let text = """
    Controls how quiet a pause must be before it can be skipped. High (−60 dBFS) protects fainter \
    sounds. Medium (−55 dBFS) and Low (−50 dBFS) allow more background noise, but may skip quiet speech.
    """
}

struct QuietAudioProtectionMenu: View {
  let mode: QuietAudioProtection
  let select: (QuietAudioProtection) -> Void

  var body: some View {
    Menu {
      ForEach(QuietAudioProtection.allCases) { choice in
        Button {
          select(choice)
        } label: {
          if choice == mode {
            AppIcon.selectionFilled.label(choice.title)
          } else {
            Text(choice.title)
          }
        }
        .accessibilityAddTraits(choice == mode ? .isSelected : [])
      }
    } label: {
      AppIcon.quietAudioProtection.image
    }
    .accessibilityLabel("Quiet Audio Protection")
    .accessibilityValue(mode.title)
  }
}

#if DEBUG
#Preview("Quiet audio protection selections") {
  VStack {
    ForEach(QuietAudioProtection.allCases) { mode in
      QuietAudioProtectionMenu(mode: mode) { _ in }
    }
  }
}
#endif
