// Copyright Justin Bishop, 2026

import FactoryKit
import Testing

@testable import PodHaven

@Suite("of TranscriptionAvailability", .container)
struct TranscriptionAvailabilityTests {
  @Test("availability starts unknown and hidden")
  func startsUnknownAndHidden() {
    let availability = Container.shared.transcriptionAvailability()

    #expect(availability.state == .unknown)
    #expect(!availability.isAvailable)
  }

  @Test("supported locale makes transcription available")
  func supportedLocaleMakesAvailable() async {
    Container.shared.speechModelManager.register {
      FakeSpeechModelManager(supportedIdentifiers: ["en-US"])
    }
    let availability = Container.shared.transcriptionAvailability()

    await availability.prepare()

    #expect(availability.state == .available)
    #expect(availability.isAvailable)
  }

  @Test("missing locale leaves transcription unavailable")
  func missingLocaleLeavesUnavailable() async {
    Container.shared.speechModelManager.register {
      FakeSpeechModelManager(supportedIdentifiers: [])
    }
    let availability = Container.shared.transcriptionAvailability()

    await availability.prepare()

    #expect(availability.state == .unavailable)
    #expect(!availability.isAvailable)
  }
}
