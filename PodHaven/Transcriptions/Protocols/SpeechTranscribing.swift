// Copyright Justin Bishop, 2026

import Foundation

// The transcription module fed by a SpeechAnalyzing, abstracted as a test seam
// the same way AVPlayableItem abstracts AVPlayerItem. The real SpeechTranscriber
// conforms in an extension; FakeSpeechTranscriber emits canned phrases.
protocol SpeechTranscribing: Sendable {
  // The module's results bridged into a Sendable stream of the abstracted
  // result type. Consume once per transcription.
  var resultStream: AsyncThrowingStream<any SpeechTranscriptionResult, any Error> { get }
}
