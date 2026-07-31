// Copyright Justin Bishop, 2026

import SwiftUI

struct TranscriptionToolbarButton: View {
  let status: TranscriptionStatus
  let transcribe: () -> Void
  let pause: () -> Void

  var body: some View {
    Button {
      if status.canPause {
        pause()
      } else {
        transcribe()
      }
    } label: {
      switch status {
      case .queued, .transcribing, .pausing:
        AppIcon.pauseTranscription.image
          .symbolEffect(.pulse, isActive: isTranscribing)
      case .discarding:
        AppIcon.discardTranscriptionProgress.image
      case .paused:
        AppIcon.resumeTranscription.image
      case .none, .transcribed, .failed:
        AppIcon.transcribeEpisode.image
      }
    }
    .accessibilityLabel(Text(LocalizedStringKey(status.toolbarAccessibilityLabel)))
    .accessibilityValue(Text(LocalizedStringKey(status.toolbarAccessibilityValue)))
    .disabled(!status.canTranscribe && !status.canPause)
  }

  private var isTranscribing: Bool {
    guard case .transcribing = status else { return false }
    return true
  }
}

extension TranscriptionStatus {
  var toolbarAccessibilityLabel: String {
    switch self {
    case .none: "Transcribe"
    case .paused: "Resume Transcription"
    case .failed: "Retry Transcription"
    case .queued, .transcribing: "Pause Transcription"
    case .pausing, .discarding, .transcribed: "Transcription"
    }
  }

  var toolbarAccessibilityValue: String {
    switch self {
    case .none: ""
    case .queued: "Queued"
    case .transcribing: "Transcribing"
    case .paused: "Paused"
    case .pausing: "Pausing"
    case .discarding: "Discarding Progress"
    case .transcribed: "Complete"
    case .failed: "Failed"
    }
  }
}
