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

        metadataRow

        Divider()

        descriptionView
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

        if !viewModel.episode.saveInCache {
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

    if let shareURL = viewModel.shareURL {
      ToolbarItem(placement: .primaryAction) {
        ShareLink(
          item: shareURL,
          preview: viewModel.sharePreview,
          label: { AppIcon.shareEpisode.label }
        )
      }
    }
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

  // MARK: - Description

  var descriptionView: some View {
    VStack(alignment: .leading, spacing: 16) {
      if let description = viewModel.episode.description, !description.isEmpty {
        VStack(alignment: .leading, spacing: 8) {
          Text("Description")
            .font(.headline)

          HTMLText(
            description,
            menuMatching: unsafe UnsavedEpisode.timestampRegex,
            menuValidator: { text, matchStart in
              matchStart == text.startIndex
                || !text[text.index(before: matchStart)].isWholeNumber
            }
          ) { timestamp in
            AppIcon.playFromHere.labelButton {
              viewModel.playAt(timestamp: timestamp)
            }
          }
        }
      }
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
        episode: DisplayedEpisode.getDisplayedEpisode(
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
        episode: DisplayedEpisode.getDisplayedEpisode(
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
        episode: DisplayedEpisode.getDisplayedEpisode(
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
        episode: DisplayedEpisode.getDisplayedEpisode(
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
#endif
