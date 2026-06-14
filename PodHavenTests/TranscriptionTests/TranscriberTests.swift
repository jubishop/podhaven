// Copyright Justin Bishop, 2026

import FactoryKit
import Foundation
import Testing

@testable import PodHaven

@Suite("of Transcriber", .container)
struct TranscriberTests {
  private let fileURL = URL(fileURLWithPath: "/dev/null")
  private let locale = Locale(identifier: "en-US")

  @Test("maps phrases to segments, trimming whitespace and dropping empties")
  func mapsPhrasesToSegments() async throws {
    TranscriptionHelpers.stubSpeech(phrases: [
      FakeSpeechTranscriptionResult(phrase: "  hello  ", startSeconds: 1.5),
      FakeSpeechTranscriptionResult(phrase: "   ", startSeconds: 2),
      FakeSpeechTranscriptionResult(phrase: "world", startSeconds: nil),
    ])

    let segments = try await Container.shared.transcriber()
      .transcribe(
        fileURL: fileURL,
        locale: locale
      )

    #expect(segments.count == 2)
    #expect(segments.first?.text == "hello")
    #expect(segments.first?.start == 1.5)
    #expect(segments.last?.text == "world")
    #expect(segments.last?.start == 0)
  }

  @Test("throws when the locale's model is unsupported")
  func throwsWhenLocaleUnsupported() async throws {
    TranscriptionHelpers.stubSpeech(
      modelManager: FakeSpeechModelManager(supportedIdentifiers: [], installedIdentifiers: [])
    )

    await #expect(throws: TranscriptionError.self) {
      try await Container.shared.transcriber().transcribe(fileURL: fileURL, locale: locale)
    }
  }

  @Test("installs the model when supported but not yet installed")
  func installsWhenNotInstalled() async throws {
    let modelManager = TranscriptionHelpers.stubSpeech(
      phrases: [FakeSpeechTranscriptionResult(phrase: "hi", startSeconds: 0)],
      modelManager: FakeSpeechModelManager(
        supportedIdentifiers: ["en-US"],
        installedIdentifiers: []
      )
    )

    let segments = try await Container.shared.transcriber()
      .transcribe(
        fileURL: fileURL,
        locale: locale
      )

    #expect(segments.first?.text == "hi")
    #expect(modelManager.installRequests() == ["en-US"])
  }

  @Test("propagates transcription failures")
  func propagatesFailures() async throws {
    TranscriptionHelpers.stubSpeechFailure()

    await #expect(throws: FakeSpeechError.self) {
      try await Container.shared.transcriber().transcribe(fileURL: fileURL, locale: locale)
    }
  }

  @Test("throws when the audio file decodes to no audio")
  func throwsWhenNoDecodableAudio() async throws {
    TranscriptionHelpers.stubSpeech(phrases: [
      FakeSpeechTranscriptionResult(phrase: "ignored", startSeconds: 0)
    ])
    Container.shared.speechAnalyzer.register { { _ in FakeSpeechAnalyzer(lastSampleTime: nil) } }

    await #expect(throws: TranscriptionError.self) {
      try await Container.shared.transcriber().transcribe(fileURL: fileURL, locale: locale)
    }
  }

  @Test("returns no segments when audio has no recognizable speech")
  func returnsNoSegmentsForSpeechlessAudio() async throws {
    TranscriptionHelpers.stubSpeech(phrases: [])

    let segments = try await Container.shared.transcriber()
      .transcribe(
        fileURL: fileURL,
        locale: locale
      )

    #expect(segments.isEmpty)
  }
}
