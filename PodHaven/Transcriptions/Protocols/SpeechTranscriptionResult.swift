// Copyright Justin Bishop, 2026

import Foundation

// One transcribed phrase from a SpeechTranscriber, abstracted so tests can
// supply results without constructing SpeechTranscriber.Result (which has no
// public initializer). The real SpeechTranscriber.Result conforms in an
// extension; FakeSpeechTranscriptionResult supplies canned values.
protocol SpeechTranscriptionResult: Sendable {
  // The phrase text exactly as transcribed, before trimming or filtering.
  var phrase: String { get }
  // Earliest audio start time across the phrase's runs, in seconds.
  var startSeconds: Double? { get }
}
