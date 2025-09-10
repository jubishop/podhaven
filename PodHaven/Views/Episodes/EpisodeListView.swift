// Copyright Justin Bishop, 2025

import AVFoundation
import FactoryKit
import NukeUI
import SwiftUI

struct EpisodeListView: View {
  @InjectedObservable(\.playState) private var playState
  @InjectedObservable(\.cacheState) private var cacheState
  @DynamicInjected(\.imageFetcher) private var imageFetcher

  private let thumbnailSize: CGFloat = 64
  private let thumbnailRoundedCorner: CGFloat = 8
  private let statusIconSize: CGFloat = 12
  @ScaledMetric(relativeTo: .caption) private var metadataIconSize: CGFloat = 12

  private let viewModel: SelectableListItemModel<any EpisodeDisplayable>

  init(viewModel: SelectableListItemModel<any EpisodeDisplayable>) {
    self.viewModel = viewModel
  }

  var body: some View {
    HStack(spacing: 4) {
      episodeImage
      statusIconColumn
      episodeInfoSection
    }
    .padding(.bottom, 12)
    .overlay(alignment: .bottom) {
      Rectangle()
        .fill(Color(uiColor: .separator))
        .frame(height: 0.5)
    }
  }

  var episodeImage: some View {
    ZStack {
      imageFetcher.lazyImage(viewModel.item.image) { state in
        if let image = state.image {
          image
            .resizable()
            .aspectRatio(contentMode: .fill)
        } else {
          Rectangle()
            .fill(Color.gray.opacity(0.4))
        }
      }
      .frame(width: thumbnailSize, height: thumbnailSize)
      .clipped()
      .cornerRadius(thumbnailRoundedCorner)

      if viewModel.isSelecting {
        Rectangle()
          .fill(Color.black.opacity(viewModel.isSelected.wrappedValue ? 0.0 : 0.6))
          .frame(width: thumbnailSize, height: thumbnailSize)
          .cornerRadius(thumbnailRoundedCorner)

        VStack {
          Spacer()
          HStack {
            Spacer()
            Button(
              action: {
                viewModel.isSelected.wrappedValue.toggle()
              },
              label: {
                (viewModel.isSelected.wrappedValue
                  ? AppLabel.selectionFilled
                  : AppLabel.selectionEmpty)
                  .image
                  .font(.system(size: thumbnailSize / 2.5))
                  .foregroundColor(viewModel.isSelected.wrappedValue ? .blue : .white)
                  .background(
                    Circle()
                      .fill(Color.black.opacity(0.8))
                      .padding(-2)
                  )
              }
            )
            .buttonStyle(BorderlessButtonStyle())
            .padding(4)
          }
        }
        .frame(width: thumbnailSize, height: thumbnailSize)
      }
    }
  }

  var statusIconColumn: some View {
    VStack(spacing: 8) {
      if let onDeck = playState.onDeck, onDeck == viewModel.item {
        AppLabel.episodeOnDeck.image
          .foregroundColor(.accentColor)
      } else if viewModel.item.queueOrder == 0 {
        AppLabel.queueAtTop.image
          .foregroundColor(.orange)
      } else {
        AppLabel.episodeQueued.image
          .foregroundColor(.orange)
          .opacity(viewModel.item.queued ? 1 : 0)
      }

      if viewModel.item.caching,
        let episodeID = viewModel.item.episodeID
      {
        if let progress = cacheState.progress(episodeID) {
          CircularProgressView(
            colorAmounts: [.green: progress],
            innerRadius: .ratio(0.4)
          )
          .frame(width: statusIconSize, height: statusIconSize)
        } else {
          AppLabel.waiting.image
            .foregroundColor(.green)
        }
      } else {
        AppLabel.episodeCached.image
          .foregroundStyle(.green)
          .opacity(viewModel.item.cached ? 1 : 0)
      }

      AppLabel.episodeCompleted.image
        .foregroundColor(.blue)
        .opacity(viewModel.item.completed ? 1 : 0)
    }
    .font(.system(size: statusIconSize))
  }

  var episodeInfoSection: some View {
    VStack(alignment: .leading, spacing: 6) {
      Text(viewModel.item.title)
        .lineLimit(2, reservesSpace: true)
        .font(.body)
        .multilineTextAlignment(.leading)
        .frame(maxWidth: .infinity, alignment: .topLeading)

      episodeMetadataRow
    }
  }

  var episodeMetadataRow: some View {
    HStack {
      HStack(spacing: 4) {
        AppLabel.publishDate.image
          .font(.system(size: metadataIconSize))
          .foregroundColor(.secondary)
        Text(viewModel.item.pubDate.usShort)
          .font(.caption)
          .foregroundColor(.secondary)
      }

      Spacer()

      HStack(spacing: 4) {
        ZStack {
          if viewModel.item.currentTime.seconds > 0 {
            CircularProgressView(
              colorAmounts: [
                .green: viewModel.item.currentTime.seconds / viewModel.item.duration.seconds
              ],
              innerRadius: .ratio(0.4)
            )
            .opacity(0.8)
            .frame(width: metadataIconSize - 2, height: metadataIconSize - 2)
          }

          AppLabel.duration.image
            .font(.system(size: metadataIconSize))
            .foregroundColor(.secondary)
        }
        Text(viewModel.item.duration.shortDescription)
          .font(.caption)
          .foregroundColor(.secondary)
      }
    }
  }
}

#if DEBUG
#Preview("All Episode Status Icons & States") {
  @Previewable @State var displayableEpisodes: [any EpisodeDisplayable] = []
  @Previewable @State var selectedStates: [Bool] = []

  List {
    Image(uiImage: UIImage(data: PreviewBundle.loadImageData(named: "changelog-podcast")!)!)
    ForEach(Array(displayableEpisodes.enumerated()), id: \.element.mediaGUID) { index, episode in
      EpisodeListView(
        viewModel: SelectableListItemModel(
          isSelected: .constant(selectedStates[safe: index] ?? false),
          item: episode,
          isSelecting: selectedStates[safe: index] ?? false
        )
      )
      .episodeListRow()
    }
  }
  .preview()
  .task {
    do {
      let repo = Container.shared.repo()
      let cacheState = Container.shared.cacheState()

      // TODO: all these dont work
      // Production HTTPS URLs that will be intercepted
      let podcastImages: [URL?] = [
        URL(string: "https://changelog.com/uploads/covers/changelog-podcast-art-2024.png"),
        URL(string: "https://media.simplecast.com/podcast/image/0c18a85f-7645-4dd4-88e1-c5de76b9b14c.jpg"),
        URL(string: "https://www.thisamericanlife.org/sites/default/files/tal-social-2024.png"),
        URL(string: "https://media.simplecast.com/podcast/image/episode1.jpg"),
        URL(string: "https://changelog.com/uploads/covers/interviews-art.png"),
        URL(string: "https://www.thisamericanlife.org/sites/default/files/episode1.jpg"),
        URL(string: "https://media.simplecast.com/podcast/image/episode2.jpg"),
        URL(string: "https://www.thisamericanlife.org/sites/default/files/episode2.jpg"),
      ]

      let basePodcast = try Create.unsavedPodcast(
        title: "PodHaven Complete Test",
        image: podcastImages[0] ?? URL.valid(),  // Use Changelog image as base or fallback
        description: "Testing all episode status icon combinations"
      )

      var episodes: [any EpisodeDisplayable] = []

      // Basic States - UnsavedPodcastEpisodes
      episodes.append(contentsOf: [
        UnsavedPodcastEpisode(
          unsavedPodcast: basePodcast,
          unsavedEpisode: try Create.unsavedEpisode(
            title: "1. Default Episode (no icons) - Grey Box",
            pubDate: Date().addingTimeInterval(-3600 * 24 * 1)
            // No image specified = uses basePodcast image (Changelog)
          )
        ),
        UnsavedPodcastEpisode(
          unsavedPodcast: try Create.unsavedPodcast(
            title: "Pod Save America",
            image: podcastImages[1] ?? URL.valid()
          ),
          unsavedEpisode: try Create.unsavedEpisode(
            title: "2. Started Episode (progress in duration)",
            pubDate: Date().addingTimeInterval(-3600 * 24 * 2),
            image: podcastImages[3],  // Episode-specific image
            currentTime: CMTime.seconds(300)
          )
        ),
        UnsavedPodcastEpisode(
          unsavedPodcast: try Create.unsavedPodcast(
            title: "This American Life",
            image: podcastImages[2] ?? URL.valid()
          ),
          unsavedEpisode: try Create.unsavedEpisode(
            title: "3. Completed Episode (blue checkmark) - SELECTED",
            pubDate: Date().addingTimeInterval(-3600 * 24 * 3),
            image: podcastImages[5],  // Episode-specific image
            completionDate: Date().addingTimeInterval(-3600 * 12)
          )
        ),
        UnsavedPodcastEpisode(
          unsavedPodcast: basePodcast,
          unsavedEpisode: try Create.unsavedEpisode(
            title: "4. Started + Completed - SELECTED",
            pubDate: Date().addingTimeInterval(-3600 * 24 * 4),
            image: podcastImages[4],  // Changelog Interviews image
            completionDate: Date().addingTimeInterval(-3600 * 6),
            currentTime: CMTime.seconds(1800)
          )
        ),
      ])

      // Queue States - UnsavedPodcastEpisodes
      episodes.append(contentsOf: [
        UnsavedPodcastEpisode(
          unsavedPodcast: try Create.unsavedPodcast(
            title: "Changelog Interviews",
            image: podcastImages[4] ?? URL.valid()
          ),
          unsavedEpisode: try Create.unsavedEpisode(
            title: "5. Queued at Top (orange arrow up)",
            pubDate: Date().addingTimeInterval(-3600 * 24 * 5),
            image: podcastImages[6],  // Pod Save America episode image
            queueOrder: 0
          )
        ),
        UnsavedPodcastEpisode(
          unsavedPodcast: basePodcast,  // Grey box - invalid image
          unsavedEpisode: try Create.unsavedEpisode(
            title: "6. Queued Middle (orange lines) - Grey Box",
            pubDate: Date().addingTimeInterval(-3600 * 24 * 6),
            image: nil,  // Will show grey box
            queueOrder: 5
          )
        ),
        UnsavedPodcastEpisode(
          unsavedPodcast: try Create.unsavedPodcast(
            title: "This American Life",
            image: podcastImages[2] ?? URL.valid()
          ),
          unsavedEpisode: try Create.unsavedEpisode(
            title: "7. Queued + Started",
            pubDate: Date().addingTimeInterval(-3600 * 24 * 7),
            image: podcastImages[7],  // This American Life episode image
            currentTime: CMTime.seconds(600),
            queueOrder: 3
          )
        ),
        UnsavedPodcastEpisode(
          unsavedPodcast: try Create.unsavedPodcast(
            title: "Pod Save America",
            image: podcastImages[1] ?? URL.valid()
          ),
          unsavedEpisode: try Create.unsavedEpisode(
            title: "8. Queued + Completed",
            pubDate: Date().addingTimeInterval(-3600 * 24 * 8),
            image: podcastImages[3],  // Pod Save America episode image
            completionDate: Date().addingTimeInterval(-3600 * 3),
            queueOrder: 2
          )
        ),
      ])

      // Cache States - UnsavedPodcastEpisodes
      episodes.append(contentsOf: [
        UnsavedPodcastEpisode(
          unsavedPodcast: try Create.unsavedPodcast(
            title: "Changelog",
            image: podcastImages[0] ?? URL.valid()
          ),
          unsavedEpisode: try Create.unsavedEpisode(
            title: "9. Cached Episode (green download)",
            pubDate: Date().addingTimeInterval(-3600 * 24 * 9),
            image: podcastImages[4],  // Changelog Interviews
            cachedFilename: "cached_episode.mp3"
          )
        ),
        UnsavedPodcastEpisode(
          unsavedPodcast: try Create.unsavedPodcast(
            title: "Unknown Podcast",
            image: URL.valid()  // Grey box
          ),
          unsavedEpisode: try Create.unsavedEpisode(
            title: "10. Cached + Started - Grey Box",
            pubDate: Date().addingTimeInterval(-3600 * 24 * 10),
            currentTime: CMTime.seconds(450),
            cachedFilename: "cached_started.mp3"
              // No episode image = falls back to podcast image (grey box)
          )
        ),
        UnsavedPodcastEpisode(
          unsavedPodcast: try Create.unsavedPodcast(
            title: "This American Life",
            image: podcastImages[2] ?? URL.valid()
          ),
          unsavedEpisode: try Create.unsavedEpisode(
            title: "11. Cached + Completed",
            pubDate: Date().addingTimeInterval(-3600 * 24 * 11),
            image: podcastImages[5],  // This American Life episode
            completionDate: Date().addingTimeInterval(-3600 * 8),
            cachedFilename: "cached_completed.mp3"
          )
        ),
        UnsavedPodcastEpisode(
          unsavedPodcast: try Create.unsavedPodcast(
            title: "Pod Save America",
            image: podcastImages[1] ?? URL.valid()
          ),
          unsavedEpisode: try Create.unsavedEpisode(
            title: "12. Cached + Queued",
            pubDate: Date().addingTimeInterval(-3600 * 24 * 12),
            image: podcastImages[6],  // Pod Save America episode 2
            queueOrder: 7,
            cachedFilename: "cached_queued.mp3"
          )
        ),
      ])

      // Caching Progress States - PodcastEpisodes (need database)
      let cachingEpisode25 = try await repo.upsertPodcastEpisode(
        UnsavedPodcastEpisode(
          unsavedPodcast: try Create.unsavedPodcast(
            title: "Changelog",
            image: podcastImages[0] ?? URL.valid()
          ),
          unsavedEpisode: try Create.unsavedEpisode(
            title: "13. Caching: 25% Progress (green circle)",
            pubDate: Date().addingTimeInterval(-3600 * 24 * 13),
            image: podcastImages[4]  // Changelog Interviews
          )
        )
      )

      let cachingEpisode65 = try await repo.upsertPodcastEpisode(
        UnsavedPodcastEpisode(
          unsavedPodcast: try Create.unsavedPodcast(
            title: "Pod Save America",
            image: podcastImages[1] ?? URL.valid()
          ),
          unsavedEpisode: try Create.unsavedEpisode(
            title: "14. Caching: 65% Progress (larger green circle)",
            pubDate: Date().addingTimeInterval(-3600 * 24 * 14),
            image: podcastImages[3]  // Pod Save America episode
          )
        )
      )

      let waitingEpisode = try await repo.upsertPodcastEpisode(
        UnsavedPodcastEpisode(
          unsavedPodcast: try Create.unsavedPodcast(
            title: "This American Life",
            image: podcastImages[2] ?? URL.valid()
          ),
          unsavedEpisode: try Create.unsavedEpisode(
            title: "15. Caching: Waiting (green clock icon)",
            pubDate: Date().addingTimeInterval(-3600 * 24 * 15),
            image: podcastImages[7]  // This American Life episode 2
          )
        )
      )

      // Set up caching states for progress episodes
      try await repo.updateDownloadTaskID(cachingEpisode25.id, URLSessionDownloadTask.ID(1))
      try await repo.updateDownloadTaskID(cachingEpisode65.id, URLSessionDownloadTask.ID(2))
      try await repo.updateDownloadTaskID(waitingEpisode.id, URLSessionDownloadTask.ID(3))

      // Simulate cache progress
      cacheState.updateProgress(for: cachingEpisode25.id, progress: 0.25)
      cacheState.updateProgress(for: cachingEpisode65.id, progress: 0.65)
      // waitingEpisode has no progress, so shows waiting icon

      // Add refreshed caching episodes to the list
      episodes.append(contentsOf: [
        try await repo.podcastEpisode(cachingEpisode25.id)!,
        try await repo.podcastEpisode(cachingEpisode65.id)!,
        try await repo.podcastEpisode(waitingEpisode.id)!,
      ])

      // Combined States - UnsavedPodcastEpisodes
      episodes.append(contentsOf: [
        UnsavedPodcastEpisode(
          unsavedPodcast: try Create.unsavedPodcast(
            title: "Changelog",
            image: podcastImages[0] ?? URL.valid()
          ),
          unsavedEpisode: try Create.unsavedEpisode(
            title: "16. Everything: Queued + Cached + Started - SELECTED",
            pubDate: Date().addingTimeInterval(-3600 * 24 * 16),
            image: podcastImages[4],  // Changelog Interviews
            currentTime: CMTime.seconds(900),
            queueOrder: 1,
            cachedFilename: "everything.mp3"
          )
        ),
        UnsavedPodcastEpisode(
          unsavedPodcast: try Create.unsavedPodcast(
            title: "Pod Save America",
            image: podcastImages[1] ?? URL.valid()
          ),
          unsavedEpisode: try Create.unsavedEpisode(
            title: "17. Top Queue + Cached + Completed",
            pubDate: Date().addingTimeInterval(-3600 * 24 * 17),
            image: podcastImages[3],  // Pod Save America episode
            completionDate: Date().addingTimeInterval(-3600 * 2),
            queueOrder: 0,
            cachedFilename: "top_queue_complete.mp3"
          )
        ),
        UnsavedPodcastEpisode(
          unsavedPodcast: try Create.unsavedPodcast(
            title: "This American Life",
            image: podcastImages[2] ?? URL.valid()
          ),
          unsavedEpisode: try Create.unsavedEpisode(
            title: "18. All States: Queue + Cache + Complete + Started",
            pubDate: Date().addingTimeInterval(-3600 * 24 * 18),
            image: podcastImages[5],  // This American Life episode
            completionDate: Date().addingTimeInterval(-3600 * 1),
            currentTime: CMTime.seconds(1500),
            queueOrder: 4,
            cachedFilename: "all_states.mp3"
          )
        ),
        UnsavedPodcastEpisode(
          unsavedPodcast: try Create.unsavedPodcast(
            title: "Changelog Interviews",
            image: podcastImages[4] ?? URL.valid()
          ),
          unsavedEpisode: try Create.unsavedEpisode(
            title: "19. Long Title to Test Layout with Multiple States and Icons - SELECTED",
            pubDate: Date().addingTimeInterval(-3600 * 24 * 19),
            image: podcastImages[6],  // Pod Save America episode 2
            currentTime: CMTime.seconds(2700),
            queueOrder: 8,
            cachedFilename: "long_title.mp3"
          )
        ),
      ])

      displayableEpisodes = episodes

      selectedStates = Array(repeating: false, count: episodes.count)
      // Set some episodes as selected for demonstration
      selectedStates[2] = true  // Completed episode
      selectedStates[3] = true  // Started + completed
      selectedStates[15] = true  // Everything episode
      selectedStates[18] = true  // Long title episode

    } catch {
      print("Error creating preview episodes: \(error)")
    }
  }
}
#endif
