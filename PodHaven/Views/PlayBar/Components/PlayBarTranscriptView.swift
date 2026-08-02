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
  let isActive: Bool

  private var attributedText: AttributedString {
    var text = AttributedString(segment.text)
    text.foregroundColor = isActive ? .primary : .secondary
    if isActive {
      text.backgroundColor = .accentColor.opacity(0.45)
    }
    return text
  }

  var body: some View {
    Text(attributedText)
      .font(.body)
      .lineSpacing(5)
      .frame(maxWidth: .infinity, alignment: .leading)
      .contentTransition(.identity)
      .accessibilityLabel(segment.text)
      .accessibilityValue("Current text block", isEnabled: isActive)
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
      text: "The current text block follows playback.",
      words: [
        TranscriptWord(start: 4, end: 4.6, text: "The"),
        TranscriptWord(start: 4.6, end: 5.2, text: " current"),
        TranscriptWord(start: 5.2, end: 5.7, text: " text"),
        TranscriptWord(start: 5.7, end: 6.4, text: " block"),
        TranscriptWord(start: 6.4, end: 7.2, text: " follows"),
        TranscriptWord(start: 7.2, end: 8, text: " playback."),
      ]
    ),
  ],
  locale: "en-US",
  createdAt: Date()
)

#Preview("synced transcript — current text block") {
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
