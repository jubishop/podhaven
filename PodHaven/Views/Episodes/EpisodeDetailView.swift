// Copyright Justin Bishop, 2025

import AVFoundation
import FactoryKit
import NukeUI
import SwiftUI

struct EpisodeDetailView: View {
  @DynamicInjected(\.alert) private var alert

  @State private var showingImageOverlay = false
  @State private var viewModel: EpisodeDetailViewModel

  init(viewModel: EpisodeDetailViewModel) {
    self.viewModel = viewModel
  }

  var body: some View {
    ScrollView {
      VStack(spacing: 16) {
        headerView
          .frame(maxWidth: .infinity)

        Divider()

        if let displayedScore = viewModel.displayedScore {
          switch displayedScore {
          case .recommendation(let score):
            recommendationSection(score: score)
          case .similarity(let value):
            similaritySection(value: value)
          case .pending:
            pendingSection
          }

          Divider()
        }

        metadataRow

        Divider()

        if viewModel.episode.isSaved {
          TagsView(
            tags: viewModel.tags,
            allTags: Container.shared.sharedState().tags,
            onAdd: viewModel.addTag,
            onRemove: viewModel.removeTag
          )

          Divider()
        }

        textContentView
      }
      .padding()
    }
    .toolbar { toolbar }
    .toolbarRole(.editor)
    .onAppear { viewModel.appear() }
    .onDisappear { viewModel.disappear() }
    .overlay {
      if showingImageOverlay {
        fullScreenImageOverlay
      }
    }
  }

  // MARK: - Toolbar

  @ToolbarContentBuilder
  private var toolbar: some ToolbarContent {
    ToolbarItem(placement: .topBarLeading) {
      Menu {
        if viewModel.isPlaying {
          AppIcon.pauseButton.labelButton {
            viewModel.pause()
          }
        } else {
          AppIcon.playNow.labelButton {
            viewModel.playNow()
          }
        }

        if viewModel.episode.queued {
          AppIcon.removeFromQueue.labelButton {
            viewModel.removeFromQueue()
          }

          if !viewModel.atTopOfQueue {
            AppIcon.moveToTop.labelButton {
              viewModel.addToTopOfQueue()
            }
          }

          if !viewModel.atBottomOfQueue {
            AppIcon.moveToBottom.labelButton {
              viewModel.appendToQueue()
            }
          }
        } else {
          AppIcon.queueAtTop.labelButton {
            viewModel.addToTopOfQueue()
          }

          AppIcon.queueAtBottom.labelButton {
            viewModel.appendToQueue()
          }
        }

        switch viewModel.episode.cacheStatus {
        case .caching:
          if viewModel.canClearCache {
            AppIcon.cancelEpisodeDownload.labelButton {
              viewModel.uncacheEpisode()
            }
          }
        case .cached:
          if viewModel.canClearCache {
            AppIcon.uncacheEpisode.labelButton {
              viewModel.uncacheEpisode()
            }
          }
        case .uncached:
          AppIcon.cacheEpisode.labelButton {
            viewModel.cacheEpisode()
          }
        }

        if viewModel.episode.saveInCache {
          AppIcon.unsaveEpisodeFromCache.labelButton {
            viewModel.unsaveEpisodeFromCache()
          }
        } else {
          AppIcon.saveEpisodeInCache.labelButton {
            viewModel.saveEpisodeInCache()
          }
        }

        if !viewModel.episode.finished {
          AppIcon.markEpisodeFinished.labelButton {
            viewModel.markFinished()
          }
        }
      } label: {
        viewModel.isPlaying ? AppIcon.pauseButton.image : AppIcon.playButton.image
      }
    }

    ToolbarItem(placement: .primaryAction) {
      ShareEpisodeButton(episode: viewModel.episode)
    }

    ToolbarItem(placement: .primaryAction) {
      Button {
        viewModel.transcribe()
      } label: {
        AppIcon.transcribeEpisode.image
          .symbolEffect(.pulse, isActive: isTranscribing)
      }
      .disabled(!viewModel.transcriptionStatus.canTranscribe)
      .accessibilityLabel(isTranscribing ? "Transcribing" : AppIcon.transcribeEpisode.text)
    }

    ToolbarItem(placement: .primaryAction) {
      Menu {
        ratingMenuButtons(showClear: viewModel.episode.rating != nil, rate: viewModel.rate)
      } label: {
        AppIcon.rating(for: viewModel.episode.rating).image
      }
    }
  }

  private var isTranscribing: Bool {
    guard case .transcribing = viewModel.transcriptionStatus else { return false }
    return true
  }

  // MARK: - Header

  private var headerView: some View {
    VStack(alignment: .center, spacing: 16) {
      HStack(spacing: 16) {
        Spacer()

        GeometryReader { geometry in
          SquareImage(
            image: viewModel.episode.image,
            cornerRadius: 16,
            size: geometry.size.width
          )
          .onTapGesture {
            showingImageOverlay = true
          }
        }
        .aspectRatio(1, contentMode: .fit)

        Spacer()
          .overlay(alignment: .leading) {
            StatusIconColumn(
              episode: viewModel.episode,
              iconSpacing: 48,
              iconSize: 28
            )
          }
      }
      .padding(.horizontal, 42)

      HTMLText(viewModel.episode.title)
        .font(.title2)
        .multilineTextAlignment(.center)

      Button(action: {
        viewModel.showPodcast()
      }) {
        Text(viewModel.episode.podcastTitle)
          .font(.headline)
          .foregroundColor(.accentColor)
          .multilineTextAlignment(.center)
          .underline()
      }
      .buttonStyle(PlainButtonStyle())
    }
  }

  // MARK: - Recommendation

  private func recommendationSection(score: RecommendationScore) -> some View {
    VStack(alignment: .leading, spacing: 8) {
      HStack(spacing: 8) {
        AppIcon.recommendation.label
        Spacer()
        Text(recommendationScoreText(score.value))
          .monospacedDigit()
          .foregroundStyle(.secondary)
      }
      .font(.headline)

      if !score.reasons.isEmpty {
        FlowLayout(horizontalSpacing: 8, verticalSpacing: 8) {
          ForEach(score.reasons.orderedMembers, id: \.self) { reason in
            AppIcon.recommendationReason(for: reason).label
              .font(.subheadline)
              .padding(.horizontal, 10)
              .padding(.vertical, 6)
              .background(Color.secondary.opacity(0.12))
              .clipShape(Capsule())
          }
        }
      }
    }
    .frame(maxWidth: .infinity, alignment: .leading)
  }

  private func recommendationScoreText(_ value: Float) -> String {
    let clamped = max(0, min(1, value))
    return "\(Int((clamped * 100).rounded()))%"
  }

  private var pendingSection: some View {
    HStack(spacing: 8) {
      AppIcon.recommendation.label
      Spacer()
      Text("Pending")
        .foregroundStyle(.secondary)
    }
    .font(.headline)
    .frame(maxWidth: .infinity, alignment: .leading)
  }

  private func similaritySection(value: Float) -> some View {
    HStack(spacing: 8) {
      AppIcon.similarityScore.label
      Spacer()
      Text(recommendationScoreText(value))
        .monospacedDigit()
        .foregroundStyle(.secondary)
    }
    .font(.headline)
    .frame(maxWidth: .infinity, alignment: .leading)
  }

  // MARK: - Metadata Row

  var metadataRow: some View {
    HStack {
      DetailedMetadataItem(
        appIcon: .publishDate,
        value: viewModel.episode.pubDate.usShortWithTime
      )

      Spacer()

      DetailedMetadataItem(
        appIcon: .duration,
        value: viewModel.episode.duration.shortDescription
      )
    }
    .dynamicTypeSize(.small ... .xxxLarge)
  }

  // MARK: - Description and Transcription

  private var textContentView: some View {
    VStack(alignment: .leading, spacing: 16) {
      Picker(
        "Episode text",
        selection: Binding(
          get: { viewModel.selectedTextTab },
          set: { viewModel.selectTextTab($0) }
        )
      ) {
        Text("Description").tag(EpisodeDetailTextTab.description)
        Text("Transcription").tag(EpisodeDetailTextTab.transcript)
      }
      .pickerStyle(.segmented)
      .frame(maxWidth: .infinity)

      switch viewModel.selectedTextTab {
      case .description:
        descriptionView
      case .transcript:
        transcriptionView
      }
    }
    .frame(maxWidth: .infinity, alignment: .leading)
  }

  var descriptionView: some View {
    VStack(alignment: .leading, spacing: 16) {
      if viewModel.episode.loaded != nil,
        let description = viewModel.episode.description,
        !description.isEmpty
      {
        descriptionText
      }
    }
    .task(id: viewModel.episode.description) {
      await viewModel.prepareDescription(font: .body)
    }
  }

  @ViewBuilder
  private var descriptionText: some View {
    if let attributed = viewModel.descriptionAttributedString {
      Text(attributed)
        .frame(maxWidth: .infinity, alignment: .leading)
        .environment(
          \.openURL,
          OpenURLAction { url in
            guard let timestamp = Timestamp.timestamp(fromURL: url) else { return .systemAction }
            alert(
              title: "Play from \(Timestamp.format(timestamp))?",
              "Start playback from this point."
            ) {
              Button("Play") { viewModel.playAt(timestamp: timestamp) }
              Button("Cancel", role: .cancel) {}
            }
            return .handled
          }
        )
    }
  }

  @ViewBuilder
  private var transcriptionView: some View {
    VStack(alignment: .leading, spacing: 8) {
      switch viewModel.transcriptionStatus {
      case .none:
        if viewModel.transcriptDisplay == .decodeFailed {
          transcriptDecodeFailureView
        } else {
          transcribeButton
        }
      case .queued(let position, let total):
        Text("Queued for transcription — position \(position) of \(total)")
          .foregroundStyle(.secondary)
      case .transcribing(let progress):
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
            Text("Transcribing…")
              .foregroundStyle(.secondary)
          }
        }
      case .transcribed:
        switch viewModel.transcriptDisplay {
        case .notTranscribed:
          transcribeButton
        case .loading:
          HStack(spacing: 8) {
            ProgressView()
            Text("Loading transcript…")
              .foregroundStyle(.secondary)
          }
        case .decodeFailed:
          transcriptDecodeFailureView
        case .empty:
          Text("No speech detected")
            .foregroundStyle(.secondary)
        case .text(let text):
          Text(text)
            .frame(maxWidth: .infinity, alignment: .leading)
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
        }
      }
    }
    .frame(maxWidth: .infinity, alignment: .leading)
  }

  private var transcribeButton: some View {
    AppIcon.transcribeEpisode
      .labelButton {
        viewModel.transcribe()
      }
      .buttonStyle(.borderedProminent)
  }

  private var transcriptDecodeFailureView: some View {
    VStack(alignment: .leading, spacing: 8) {
      Text("Transcript couldn't be read")
        .foregroundStyle(.red)
      Text("Transcribe again to replace the unreadable transcript.")
        .foregroundStyle(.secondary)
      AppIcon.transcribeEpisode
        .labelButton("Transcribe Again") {
          viewModel.transcribe()
        }
        .buttonStyle(.bordered)
    }
  }

  // MARK: - Full Screen Image Overlay

  private var fullScreenImageOverlay: some View {
    ZStack {
      Color.black
        .opacity(0.92)
        .ignoresSafeArea()

      PipelinedLazyImage(url: viewModel.episode.image) { state in
        if let image = state.image {
          image
            .resizable()
            .aspectRatio(contentMode: .fit)
            .clipShape(RoundedRectangle(cornerRadius: 16))
            .padding(4)
        } else {
          VStack(spacing: 16) {
            AppIcon.noImage.image
              .font(.largeTitle)
              .foregroundColor(.secondary)

            Text("Image unavailable")
              .font(.title)
              .foregroundColor(.secondary)

            Text("Tap to close")
              .font(.headline)
              .foregroundColor(.secondary)
          }
        }
      }
    }
    .onTapGesture {
      showingImageOverlay = false
    }
  }
}

// MARK: - Preview

#if DEBUG
#Preview("Basic Episode") {
  NavigationStack {
    EpisodeDetailView(
      viewModel: EpisodeDetailViewModel(
        episode: DisplayedEpisode(
          UnsavedPodcastEpisode(
            unsavedPodcast: try! Create.unsavedPodcast(
              title: "The Tech Podcast",
              description: "A podcast about technology and innovation"
            ),
            unsavedEpisode: try! Create.unsavedEpisode(
              title: "Introduction to SwiftUI",
              pubDate: Date().addingTimeInterval(-86400 * 7),
              duration: CMTime(seconds: 3600, preferredTimescale: 1),
              description: """
                <p>In this episode, we dive deep into SwiftUI and explore how to build beautiful, \
                modern user interfaces for iOS applications.</p>
                <p>We'll cover:</p>
                <ul>
                  <li>The basics of SwiftUI views</li>
                  <li>State management with @State and @Binding</li>
                  <li>Building custom components</li>
                  <li>Best practices for SwiftUI development</li>
                </ul>
                """
            )
          )
        )
      )
    )
    .preview()
  }
}

#Preview("Long Title & Description") {
  NavigationStack {
    EpisodeDetailView(
      viewModel: EpisodeDetailViewModel(
        episode: DisplayedEpisode(
          UnsavedPodcastEpisode(
            unsavedPodcast: try! Create.unsavedPodcast(
              title: "The Long-Form Investigative Journalism and Documentary Podcast Network",
              description: "In-depth investigative journalism covering complex topics"
            ),
            unsavedEpisode: try! Create.unsavedEpisode(
              title:
                """
                Episode 127: A Deep Dive Into the Complex World of International Climate Policy, \
                Carbon Markets, and the Future of Renewable Energy Infrastructure Development
                """,
              pubDate: Date().addingTimeInterval(-86400),
              duration: CMTime(seconds: 7200, preferredTimescale: 1),
              description: """
                <p>This comprehensive episode examines the intricate relationships between international \
                climate agreements, carbon trading markets, and the development of renewable energy \
                infrastructure across multiple continents.</p>
                <h2>Part 1: Climate Policy Frameworks</h2>
                <p>We begin with an analysis of current international climate policy frameworks, including \
                the Paris Agreement and regional initiatives.</p>
                <h2>Part 2: Carbon Markets</h2>
                <p>An exploration of how carbon markets function, their effectiveness, and ongoing debates \
                about their role in climate mitigation.</p>
                <h2>Part 3: Renewable Energy Infrastructure</h2>
                <p>Examining the challenges and opportunities in developing renewable energy infrastructure \
                at scale, from solar farms to offshore wind installations.</p>
                <h2>Expert Interviews</h2>
                <ul>
                  <li>Dr. Sarah Chen - Climate Policy Expert</li>
                  <li>Michael Torres - Carbon Market Analyst</li>
                  <li>Dr. Amara Okafor - Renewable Energy Engineer</li>
                  <li>Prof. Lars Eriksson - Environmental Economist</li>
                </ul>
                """
            )
          )
        )
      )
    )
    .preview()
  }
}

#Preview("Episode with Timestamps") {
  NavigationStack {
    EpisodeDetailView(
      viewModel: EpisodeDetailViewModel(
        episode: DisplayedEpisode(
          UnsavedPodcastEpisode(
            unsavedPodcast: try! Create.unsavedPodcast(
              title: "Tech Interview Podcast",
              description: "Deep dives into technology topics"
            ),
            unsavedEpisode: try! Create.unsavedEpisode(
              title: "Episode 42: The Future of AI",
              pubDate: Date().addingTimeInterval(-86400 * 2),
              duration: CMTime(seconds: 5400, preferredTimescale: 1),
              description: """
                <p>In this episode we cover a range of AI topics:</p>
                <p>0:00 Introduction<br/>\
                2:15 What is machine learning?<br/>\
                14:30 Neural networks explained<br/>\
                28:45 The future of large language models<br/>\
                1:02:15 Q&amp;A session</p>
                <p>Visit <a href="https://example.com">our website</a> for show notes.</p>
                """
            )
          )
        )
      )
    )
    .preview()
  }
}

#Preview("Full Status Icons") {
  NavigationStack {
    EpisodeDetailView(
      viewModel: EpisodeDetailViewModel(
        episode: DisplayedEpisode(
          UnsavedPodcastEpisode(
            unsavedPodcast: try! Create.unsavedPodcast(
              title: "Tech Talk Daily",
              description: "Your daily dose of tech news"
            ),
            unsavedEpisode: try! Create.unsavedEpisode(
              title: "AI Advances in 2025",
              pubDate: Date().addingTimeInterval(-86400 * 3),
              duration: CMTime(seconds: 3600, preferredTimescale: 1),
              description: "<p>Exploring the latest advances in artificial intelligence.</p>",
              currentTime: CMTime(seconds: 1800, preferredTimescale: 1),
              queueOrder: 2,
              queueDate: Date().addingTimeInterval(-1800),
              cachedFilename: "cached_episode.mp3"
            )
          )
        )
      )
    )
    .preview()
  }
}

#Preview("Strong Recommendation") {
  let viewModel = EpisodeDetailViewModel(
    episode: DisplayedEpisode(
      UnsavedPodcastEpisode(
        unsavedPodcast: try! Create.unsavedPodcast(
          title: "The Tech Podcast",
          description: "A podcast about technology and innovation"
        ),
        unsavedEpisode: try! Create.unsavedEpisode(
          title: "Why Vector Search Eats Keyword Search for Breakfast",
          pubDate: Date().addingTimeInterval(-86400),
          duration: CMTime(seconds: 2700, preferredTimescale: 1),
          description: """
            <p>Embeddings, ANN indexes, and the surprising places semantic \
            search shows up in modern apps.</p>
            """
        )
      )
    )
  )
  viewModel.previewSeedDisplayedScore(
    .recommendation(
      RecommendationScore(
        value: 0.87,
        reasons: [.similarToLiked, .podcastAffinity, .recentlyPublished]
      )
    )
  )
  return NavigationStack {
    EpisodeDetailView(viewModel: viewModel)
      .preview()
  }
}

#Preview("Recommendation, Single Reason") {
  let viewModel = EpisodeDetailViewModel(
    episode: DisplayedEpisode(
      UnsavedPodcastEpisode(
        unsavedPodcast: try! Create.unsavedPodcast(
          title: "Curious Minds Weekly",
          description: "Conversations across science, history, and culture"
        ),
        unsavedEpisode: try! Create.unsavedEpisode(
          title: "The Hidden History of the Decimal Point",
          pubDate: Date().addingTimeInterval(-86400 * 30),
          duration: CMTime(seconds: 3300, preferredTimescale: 1),
          description: "<p>A deceptively rich story about a tiny dot.</p>"
        )
      )
    )
  )
  viewModel.previewSeedDisplayedScore(
    .recommendation(RecommendationScore(value: 0.42, reasons: [.similarToLiked]))
  )
  return NavigationStack {
    EpisodeDetailView(viewModel: viewModel)
      .preview()
  }
}

#Preview("Pending (Saved)") {
  let viewModel = EpisodeDetailViewModel(
    episode: DisplayedEpisode(
      UnsavedPodcastEpisode(
        unsavedPodcast: try! Create.unsavedPodcast(
          title: "Newly Saved Podcast",
          description: "Saved before the embedding pipeline has run"
        ),
        unsavedEpisode: try! Create.unsavedEpisode(
          title: "Awaiting Embedding",
          pubDate: Date().addingTimeInterval(-3600),
          duration: CMTime(seconds: 1800, preferredTimescale: 1),
          description:
            "<p>The recommendation score will surface once the embedding is computed.</p>"
        )
      )
    )
  )
  viewModel.previewSeedDisplayedScore(.pending)
  return NavigationStack {
    EpisodeDetailView(viewModel: viewModel)
      .preview()
  }
}

#Preview("Similarity Score (Unsaved)") {
  let viewModel = EpisodeDetailViewModel(
    episode: DisplayedEpisode(
      UnsavedPodcastEpisode(
        unsavedPodcast: try! Create.unsavedPodcast(
          title: "Search Result Podcast",
          description: "A podcast surfaced from search"
        ),
        unsavedEpisode: try! Create.unsavedEpisode(
          title: "An Unsaved Discovery",
          pubDate: Date().addingTimeInterval(-86400 * 7),
          duration: CMTime(seconds: 2400, preferredTimescale: 1),
          description: "<p>An episode the user hasn't saved yet.</p>"
        )
      )
    )
  )
  viewModel.previewSeedDisplayedScore(.similarity(0.73))
  return NavigationStack {
    EpisodeDetailView(viewModel: viewModel)
      .preview()
  }
}
#endif
