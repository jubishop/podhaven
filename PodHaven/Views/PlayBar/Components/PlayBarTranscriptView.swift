// Copyright Justin Bishop, 2026

import SwiftUI

struct PlayBarTranscriptView: View {
  let transcript: Transcript
  let currentTime: TimeInterval

  @Environment(\.accessibilityReduceMotion) private var accessibilityReduceMotion

  private var activeSegmentIndex: Int? {
    transcript.activeSegmentIndex(at: currentTime)
  }

  var body: some View {
    ScrollViewReader { proxy in
      ScrollView {
        LazyVStack(alignment: .leading, spacing: 18) {
          ForEach(transcript.segments.indices, id: \.self) { index in
            PlayBarTranscriptSegmentView(
              segment: transcript.segments[index],
              currentTime: currentTime,
              isActive: index == activeSegmentIndex
            )
            .id(index)
          }
        }
        .padding(16)
      }
      .scrollIndicators(.hidden)
      .onChange(of: activeSegmentIndex, initial: true) { _, activeSegmentIndex in
        guard let activeSegmentIndex else { return }
        withAnimation(accessibilityReduceMotion ? nil : .easeInOut(duration: 0.35)) {
          proxy.scrollTo(activeSegmentIndex, anchor: .center)
        }
      }
    }
    .background(.ultraThinMaterial, in: .rect(cornerRadius: 16))
    .accessibilityElement(children: .contain)
    .accessibilityLabel("Synchronized Transcript")
  }
}

private struct PlayBarTranscriptSegmentView: View {
  let segment: TranscriptSegment
  let currentTime: TimeInterval
  let isActive: Bool

  @Environment(\.accessibilityReduceMotion) private var accessibilityReduceMotion

  private var words: [TranscriptWord] {
    segment.playbackWords
  }

  private var activeWordIndex: Int? {
    guard isActive else { return nil }
    return segment.activeWordIndex(at: currentTime)
  }

  private var activeWordText: String? {
    guard let activeWordIndex else { return nil }
    let text = words[activeWordIndex].text.trimmed()
    return text.isEmpty ? nil : text
  }

  private var attributedText: AttributedString {
    var result = AttributedString()
    for (index, word) in words.enumerated() {
      var text = AttributedString(word.text)
      if index == activeWordIndex {
        text.foregroundColor = .primary
        text.backgroundColor = .accentColor.opacity(0.45)
        text.font = .body.weight(.semibold)
      } else {
        text.foregroundColor = isActive ? .primary.opacity(0.8) : .secondary
      }
      result.append(text)
    }
    return result
  }

  var body: some View {
    Text(attributedText)
      .font(.body)
      .lineSpacing(5)
      .frame(maxWidth: .infinity, alignment: .leading)
      .contentTransition(.interpolate)
      .animation(
        accessibilityReduceMotion ? nil : .easeInOut(duration: 0.2),
        value: activeWordIndex
      )
      .accessibilityLabel(segment.text)
      .accessibilityValue(
        activeWordText.map { "Current word \($0)" } ?? ""
      )
  }
}

// MARK: - Previews

#if DEBUG
private let previewPlayBarTranscript = Transcript(
  segments: [
    TranscriptSegment(
      start: 0,
      end: 4,
      text: "Welcome to the synchronized transcript.",
      words: [
        TranscriptWord(start: 0, end: 0.8, text: "Welcome"),
        TranscriptWord(start: 0.8, end: 1.2, text: " to"),
        TranscriptWord(start: 1.2, end: 1.8, text: " the"),
        TranscriptWord(start: 1.8, end: 3, text: " synchronized"),
        TranscriptWord(start: 3, end: 4, text: " transcript."),
      ]
    ),
    TranscriptSegment(
      start: 4,
      end: 8,
      text: "The current word follows playback.",
      words: [
        TranscriptWord(start: 4, end: 4.7, text: "The"),
        TranscriptWord(start: 4.7, end: 5.5, text: " current"),
        TranscriptWord(start: 5.5, end: 6.1, text: " word"),
        TranscriptWord(start: 6.1, end: 7, text: " follows"),
        TranscriptWord(start: 7, end: 8, text: " playback."),
      ]
    ),
  ],
  locale: "en-US",
  createdAt: Date()
)

#Preview("synced transcript — current word") {
  ZStack {
    LinearGradient(
      colors: [.purple.opacity(0.8), .blue.opacity(0.8)],
      startPoint: .topLeading,
      endPoint: .bottomTrailing
    )
    PlayBarTranscriptView(transcript: previewPlayBarTranscript, currentTime: 5.8)
      .padding()
  }
  .frame(width: 390, height: 520)
}

#Preview("synced transcript — legacy phrase timing") {
  ZStack {
    Color.indigo
    PlayBarTranscriptView(
      transcript: Transcript(
        segments: [TranscriptSegment(start: 0, end: 4, text: "Legacy transcript phrase")],
        locale: "en-US",
        createdAt: Date()
      ),
      currentTime: 2
    )
    .padding()
  }
  .frame(width: 390, height: 320)
}
#endif
