// Copyright Justin Bishop, 2026

import FactoryKit
import Observation
import SwiftUI
import Testing

@testable import PodHaven

@Suite("Player preview lifecycle", .container)
@MainActor struct PlayBarPreviewTests {
  @Test("cancelled fixture setup leaves the player empty and a fresh transcript preview loads")
  func cancelledSetup() async throws {
    let state = Container.shared.sharedState()
    state.setPlaybackStatus(.paused)
    let cancelled = ThreadSafe(false)
    withObservationTracking {
      _ = state.playbackStatus
    } onChange: {
      withUnsafeCurrentTask { task in
        task?.cancel()
        cancelled(Task.isCancelled)
      }
    }

    try await LogCapture.withSink { sink in
      try await withHostedTestWindow(
        TestHostingController(rootView: PlayBarSheetPreview(image: nil))
      ) { _ in
        try await Wait.until {
          sink.captured().contains { $0.message.contains("Could not prepare player preview") }
        } _: {
          "Cancelled preview setup did not finish"
        }
        #expect(cancelled())
        #expect(state.onDeck == nil)
      }
    }

    let transcript = Transcript(
      segments: [TranscriptSegment(start: 0, end: 12, text: "Preview transcript")],
      locale: "en-US",
      createdAt: Date()
    )
    try await withHostedTestWindow(
      TestHostingController(
        rootView: PlayBarSheetPreview(
          image: nil,
          duration: 12,
          transcript: transcript,
          silenceMode: .balanced,
          quietAudioProtection: .medium
        )
      )
    ) { _ in
      try await Wait.until {
        state.onDeck?.hasTranscript == true
      } _: {
        "Fresh preview did not load its transcript"
      }
      #expect(state.effectiveSilenceMode == .balanced)
      #expect(state.effectiveQuietAudioProtection == .medium)
    }
  }
}
