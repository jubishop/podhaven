// Copyright Justin Bishop, 2026

import SwiftUI

enum SilenceSettingsHelp {
  static let text = """
    Shortens clear pauses while keeping natural space around speech. Gentle keeps more space, \
    Balanced shortens more, and Aggressive removes the most. Higher playback speeds shorten \
    pauses a little more automatically. Off keeps the original pauses.

    Requires downloaded audio and completed audio analysis. Playback continues normally while \
    analysis is pending. Pauses aren't shortened during CarPlay playback.
    """
}

struct SilenceModeMenu: View {
  let mode: SilenceMode
  let select: (SilenceMode) -> Void

  var body: some View {
    Menu {
      ForEach(SilenceMode.allCases) { choice in
        Button {
          select(choice)
        } label: {
          if choice == mode {
            AppIcon.selectionFilled.label(choice.title)
          } else {
            Text(choice.title)
          }
        }
      }
    } label: {
      AppIcon.silence.image
    }
  }
}

#if DEBUG
#Preview("Silence selections") {
  VStack {
    ForEach(SilenceMode.allCases) { mode in
      SilenceModeMenu(mode: mode) { _ in }
    }
  }
}
#endif
