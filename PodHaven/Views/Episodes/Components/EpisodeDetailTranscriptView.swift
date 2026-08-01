// Copyright Justin Bishop, 2026

import FactoryKit
import Logging
import SwiftUI

struct TranscriptDecodeFailureView: View {
  let canTranscribeAgain: Bool
  let transcribe: () -> Void

  var body: some View {
    VStack(alignment: .leading, spacing: 8) {
      Text("Transcript couldn't be read")
        .foregroundStyle(.red)
      Text(
        canTranscribeAgain
          ? "Transcribe again to replace the unreadable transcript."
          : "On-device transcription isn't available to replace it."
      )
      .foregroundStyle(.secondary)
      if canTranscribeAgain {
        AppIcon.transcribeEpisode
          .labelButton("Transcribe Again") {
            transcribe()
          }
          .buttonStyle(.bordered)
      }
    }
  }
}

struct EpisodeDetailTranscriptView: View {
  @ScaledMetric(relativeTo: .body) private var paragraphSpacing: CGFloat = 16
  @State private var showingDiscardProgressConfirmation = false
  @Bindable var viewModel: EpisodeDetailViewModel

  init(viewModel: EpisodeDetailViewModel) {
    self.viewModel = viewModel
  }

  var body: some View {
    VStack(alignment: .leading, spacing: 8) {
      if let provenance = viewModel.transcriptProvenance {
        LabeledContent(
          "Transcript source",
          value: provenance.accessibilityValue
        )
        .font(.subheadline)
        .foregroundStyle(.secondary)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Transcript source")
        .accessibilityValue(provenance.accessibilityValue)
      }

      statusView

      if showsCanonicalTranscriptAlongsideWork {
        Divider()
          .padding(.vertical, 8)
        canonicalTranscriptContent
      }
    }
    .frame(maxWidth: .infinity, alignment: .leading)
    .padding(.bottom, bottomPadding)
    .confirmationDialog(
      "Discard Transcription Progress?",
      isPresented: $showingDiscardProgressConfirmation,
      titleVisibility: .visible
    ) {
      Button("Discard Progress", role: .destructive) {
        viewModel.discardTranscriptionProgress()
      }
      Button("Cancel", role: .cancel) {}
    } message: {
      Text(discardMessage)
    }
  }

  private var discardMessage: String {
    if viewModel.transcriptProvenance == .podcastFeed {
      return
        """
        This permanently deletes all saved on-device replacement progress and stops the work if it \
        is running. The podcast feed transcript will remain available.
        """
    }
    return
      """
      This permanently deletes all saved progress and stops the transcription if it is running. \
      The next transcription will start from the beginning.
      """
  }

  @ViewBuilder
  private var statusView: some View {
    switch viewModel.transcriptionStatus {
    case .none:
      if viewModel.transcriptDisplay == .decodeFailed {
        transcriptDecodeFailureView
      } else {
        transcribeButton
      }
    case .queued(let position, let total):
      VStack(alignment: .leading, spacing: 8) {
        Text("Queued for transcription — position \(position) of \(total)")
          .foregroundStyle(.secondary)
        pauseTranscriptionButton
        if viewModel.canDiscardTranscriptionProgress {
          discardTranscriptionProgressButton
        }
      }
    case .transcribing(let progress):
      VStack(alignment: .leading, spacing: 8) {
        if progress > 0 {
          ProgressView(value: progress) {
            Text("Transcribing…")
              .foregroundStyle(.secondary)
          } currentValueLabel: {
            Text(progress, format: .percent.precision(.fractionLength(0)))
              .foregroundStyle(.secondary)
          }
        } else {
          HStack(spacing: 8) {
            ProgressView()
              .accessibilityHidden(true)
            Text("Transcribing…")
              .foregroundStyle(.secondary)
          }
        }
        pauseTranscriptionButton
        discardTranscriptionProgressButton
      }
    case .paused(let progress):
      VStack(alignment: .leading, spacing: 8) {
        ProgressView(value: progress) {
          Text("Transcription paused")
            .foregroundStyle(.secondary)
        } currentValueLabel: {
          Text(progress, format: .percent.precision(.fractionLength(0)))
            .foregroundStyle(.secondary)
        }
        resumeTranscriptionButton
        discardTranscriptionProgressButton
      }
    case .pausing:
      HStack(spacing: 8) {
        ProgressView()
          .accessibilityHidden(true)
        Text("Pausing transcription…")
          .foregroundStyle(.secondary)
      }
    case .discarding:
      HStack(spacing: 8) {
        ProgressView()
          .accessibilityHidden(true)
        Text("Discarding transcription progress…")
          .foregroundStyle(.secondary)
      }
    case .transcribed:
      VStack(alignment: .leading, spacing: 8) {
        if viewModel.canReplacePublisherTranscript {
          replacePublisherTranscriptButton
        }
        transcriptContent
      }
    case .failed:
      VStack(alignment: .leading, spacing: 8) {
        Text("Transcription failed")
          .foregroundStyle(.red)
        AppIcon.transcribeEpisode
          .labelButton("Retry") {
            viewModel.transcribe()
          }
          .buttonStyle(.bordered)
        if viewModel.canDiscardTranscriptionProgress {
          discardTranscriptionProgressButton
        }
      }
    }
  }

  private var showsCanonicalTranscriptAlongsideWork: Bool {
    guard viewModel.transcriptProvenance == .podcastFeed else { return false }
    switch viewModel.transcriptionStatus {
    case .queued, .transcribing, .paused, .pausing, .discarding, .failed:
      return true
    case .none, .transcribed:
      return false
    }
  }

  @ViewBuilder
  private var transcriptContent: some View {
    switch viewModel.transcriptDisplay {
    case .notTranscribed:
      transcribeButton
    case .loading:
      HStack(spacing: 8) {
        ProgressView()
          .accessibilityHidden(true)
        Text("Loading transcript…")
          .foregroundStyle(.secondary)
      }
    case .decodeFailed:
      transcriptDecodeFailureView
    case .empty:
      Text("No speech detected")
        .foregroundStyle(.secondary)
    case .text:
      canonicalTranscriptContent
    }
  }

  @ViewBuilder
  private var canonicalTranscriptContent: some View {
    switch viewModel.transcriptDisplay {
    case .empty:
      Text("No speech detected")
        .foregroundStyle(.secondary)
    case .text(let segments):
      LazyVStack(alignment: .leading, spacing: paragraphSpacing) {
        ForEach(segments.indices, id: \.self) { index in
          Text(segments[index].text)
        }
      }
      .frame(maxWidth: .infinity, alignment: .leading)
    case .notTranscribed, .loading, .decodeFailed:
      EmptyView()
    }
  }

  private var bottomPadding: CGFloat {
    switch viewModel.transcriptDisplay {
    case .notTranscribed, .loading, .decodeFailed, .empty: 8
    case .text: 0
    }
  }

  private var transcribeButton: some View {
    AppIcon.transcribeEpisode
      .labelButton {
        viewModel.transcribe()
      }
      .buttonStyle(.bordered)
  }

  private var replacePublisherTranscriptButton: some View {
    AppIcon.transcribeEpisode
      .labelButton("Replace with On-Device Transcription") {
        viewModel.transcribe()
      }
      .buttonStyle(.bordered)
  }

  private var pauseTranscriptionButton: some View {
    AppIcon.pauseTranscription
      .labelButton {
        viewModel.pauseTranscription()
      }
      .buttonStyle(.bordered)
  }

  private var resumeTranscriptionButton: some View {
    AppIcon.resumeTranscription
      .labelButton {
        viewModel.transcribe()
      }
      .buttonStyle(.bordered)
  }

  private var discardTranscriptionProgressButton: some View {
    AppIcon.discardTranscriptionProgress
      .labelButton {
        showingDiscardProgressConfirmation = true
      }
      .buttonStyle(.bordered)
      .tint(.red)
  }

  private var transcriptDecodeFailureView: some View {
    TranscriptDecodeFailureView(
      canTranscribeAgain: viewModel.isTranscriptionAvailable,
      transcribe: viewModel.transcribe
    )
  }
}

#if DEBUG
@MainActor private struct EpisodeDetailTranscriptPreview: View {
  enum Source {
    case podcastFeed
    case onDevice
  }

  let source: Source
  let supportsReplacement: Bool
  @State private var viewModel: EpisodeDetailViewModel?

  private static let log = Log.as(LogSubsystem.EpisodesView.detail)

  var body: some View {
    Group {
      if let viewModel {
        EpisodeDetailTranscriptView(viewModel: viewModel)
      } else {
        ProgressView("Loading transcript preview…")
      }
    }
    .padding()
    .task {
      guard viewModel == nil else { return }
      Container.shared.transcriptionAvailability().$state
        .new(
          supportsReplacement ? .available : .unavailable
        )
      do {
        let podcastEpisode = try await Create.podcastEpisode()
        let transcript = Transcript(
          segments: [
            TranscriptSegment(
              start: 0,
              end: 4,
              text: "Representative words from the saved episode transcript."
            )
          ],
          locale: "en-US",
          createdAt: Date(timeIntervalSince1970: 0)
        )
        switch source {
        case .podcastFeed:
          guard let url = URL(string: "https://example.com/preview.vtt")
          else { return }
          let stored = try await Container.shared.repo()
            .storeTranscriptIfAbsent(
              podcastEpisode.id,
              transcript: transcript,
              publisherSource: PublisherTranscriptReference(
                url: url,
                mimeType: "text/vtt",
                language: "en-US"
              )
            )
          guard stored else { return }
        case .onDevice:
          try await Container.shared.repo()
            .updateTranscript(
              podcastEpisode.id,
              transcript: transcript.jsonString()
            )
        }
        guard
          let loaded = try await Container.shared.repo()
            .podcastEpisode(
              podcastEpisode.id
            )
        else {
          return
        }
        viewModel = EpisodeDetailViewModel(episode: DisplayedEpisode(loaded))
      } catch {
        Self.log.caughtError("Failed to build transcript preview", error)
      }
    }
  }
}

#Preview("Publisher Transcript Replacement") {
  EpisodeDetailTranscriptPreview(
    source: .podcastFeed,
    supportsReplacement: true
  )
}

#Preview("Publisher Transcript Unsupported Device") {
  EpisodeDetailTranscriptPreview(
    source: .podcastFeed,
    supportsReplacement: false
  )
}

#Preview("On-Device Transcript") {
  EpisodeDetailTranscriptPreview(
    source: .onDevice,
    supportsReplacement: true
  )
}
#endif
