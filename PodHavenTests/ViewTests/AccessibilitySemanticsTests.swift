// Copyright Justin Bishop, 2026

import Testing

@testable import PodHaven

@Suite("of accessibility semantics tests", .container)
@MainActor struct AccessibilitySemanticsTests {
  @Test("seek actions include their configured interval")
  func seekActionsIncludeTheirConfiguredInterval() {
    #expect(AppIcon.seekBackward(30).text == "Seek Backward 30 Seconds")
    #expect(AppIcon.seekForward(45).text == "Seek Forward 45 Seconds")
  }

  @Test("selection controls describe the action they perform")
  func selectionControlsDescribeTheirAction() {
    #expect(AppIcon.selectionEmpty.text == "Select")
    #expect(AppIcon.selectionFilled.text == "Deselect")
  }

  @Test("transcription toolbar distinguishes actions and states")
  func transcriptionToolbarDistinguishesActionsAndStates() {
    #expect(TranscriptionStatus.none.toolbarAccessibilityLabel == "Transcribe")
    #expect(TranscriptionStatus.none.toolbarAccessibilityValue == "")
    #expect(TranscriptionStatus.queued.toolbarAccessibilityLabel == "Transcription")
    #expect(TranscriptionStatus.queued.toolbarAccessibilityValue == "Queued")
    #expect(TranscriptionStatus.transcribing(0.5).toolbarAccessibilityLabel == "Transcription")
    #expect(TranscriptionStatus.transcribing(0.5).toolbarAccessibilityValue == "Transcribing")
    #expect(TranscriptionStatus.transcribed.toolbarAccessibilityLabel == "Transcription")
    #expect(TranscriptionStatus.transcribed.toolbarAccessibilityValue == "Complete")
    #expect(TranscriptionStatus.failed.toolbarAccessibilityLabel == "Retry Transcription")
    #expect(TranscriptionStatus.failed.toolbarAccessibilityValue == "Failed")
  }
}
