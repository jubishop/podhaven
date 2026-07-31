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

#if DEBUG
private struct TranscriptionToolbarButtonPreview: View {
  private struct PreviewStatus: Identifiable {
    let name: String
    let status: TranscriptionStatus

    var id: String { name }
  }

  private let statuses = [
    PreviewStatus(name: "None", status: .none),
    PreviewStatus(name: "Queued", status: .queued(position: 1, total: 2)),
    PreviewStatus(name: "Transcribing", status: .transcribing(0.5)),
    PreviewStatus(name: "Pausing", status: .pausing),
    PreviewStatus(name: "Discarding", status: .discarding),
    PreviewStatus(name: "Paused", status: .paused(0.5)),
    PreviewStatus(name: "Transcribed", status: .transcribed),
    PreviewStatus(name: "Failed", status: .failed),
  ]

  var body: some View {
    VStack(spacing: 16) {
      ForEach(statuses) { previewStatus in
        HStack {
          Text(previewStatus.name)
          Spacer()
          TranscriptionToolbarButton(
            status: previewStatus.status,
            transcribe: {},
            pause: {}
          )
        }
      }
    }
    .padding()
  }
}

#Preview("Transcription States") {
  TranscriptionToolbarButtonPreview()
}
#endif
