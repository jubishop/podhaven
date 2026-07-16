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

  @Test("playback status icons announce their actual state")
  func playbackStatusIconsAnnounceTheirActualState() {
    #expect(PlaybackStatus.playing.statusIconAccessibilityLabel == "Playing")
    #expect(PlaybackStatus.waiting.statusIconAccessibilityLabel == "Waiting to Play")
    #expect(PlaybackStatus.paused.statusIconAccessibilityLabel == "Paused")
    #expect(PlaybackStatus.loading("Episode").statusIconAccessibilityLabel == "Loading")
    #expect(PlaybackStatus.stopped.statusIconAccessibilityLabel == "Stopped")
  }
}
