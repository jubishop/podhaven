// Copyright Justin Bishop, 2025

import AVFoundation
import FactoryKit
import SwiftUI

struct EpisodeListView: View {
  @InjectedObservable(\.playState) private var playState
  @InjectedObservable(\.cacheState) private var cacheState

  private let thumbnailSize: CGFloat = 64
  private let statusIconSize: CGFloat = 12
  @ScaledMetric(relativeTo: .caption) private var metadataIconSize: CGFloat = 12

  private let episode: any EpisodeDisplayable
  private let isSelecting: Bool
  private let isSelected: Binding<Bool>
  init(
    episode: any EpisodeDisplayable,
    isSelecting: Bool = false,
    isSelected: Binding<Bool> = .constant(false)
  ) {
    self.episode = episode
    self.isSelecting = isSelecting
    self.isSelected = isSelected
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
    SelectableSquareImage(
      image: episode.image,
      size: .constant(thumbnailSize),
      isSelected: isSelected,
      isSelecting: isSelecting
    )
    .frame(width: thumbnailSize)
  }

  var statusIconColumn: some View {
    VStack(spacing: 8) {
      if let onDeck = playState.onDeck, onDeck == episode {
        AppLabel.episodeOnDeck.image
          .foregroundColor(.accentColor)
      } else if episode.queueOrder == 0 {
        AppLabel.queueAtTop.image
          .foregroundColor(.orange)
      } else {
        AppLabel.episodeQueued.image
          .foregroundColor(.orange)
          .opacity(episode.queued ? 1 : 0)
      }

      if episode.cacheStatus == .caching,
        let episodeID = episode.episodeID
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
          .opacity(episode.cacheStatus == .cached ? 1 : 0)
      }

      AppLabel.episodeFinished.image
        .foregroundColor(.blue)
        .opacity(episode.finished ? 1 : 0)
    }
    .font(.system(size: statusIconSize))
  }

  var episodeInfoSection: some View {
    VStack(alignment: .leading, spacing: 6) {
      Text(episode.title)
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
        Text(episode.pubDate.usShort)
          .font(.caption)
          .foregroundColor(.secondary)
      }

      Spacer()

      HStack(spacing: 4) {
        ZStack {
          if episode.currentTime.seconds > 0 {
            CircularProgressView(
              colorAmounts: [
                .green: episode.currentTime.seconds / episode.duration.seconds
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
        Text(episode.duration.shortDescription)
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
  @Previewable @State var isSelected: Bool = false

  NavigationStack {
    List {
      ForEach(Array(displayableEpisodes.enumerated()), id: \.element.mediaGUID) { index, episode in
        NavigationLink {
        } label: {
          EpisodeListView(
            episode: episode,
            isSelecting: selectedStates[safe: index] ?? false,
            isSelected: $isSelected
          )
          .episodeListRow()
        }
      }
    }
  }
  .preview()
  .task {
    do {
      let cacheState = Container.shared.cacheState()
      let dataLoader = Container.shared.fakeDataLoader()
      let repo = Container.shared.repo()

      let imageMapping = [
        "changelog-podcast": URL.valid(),
        "changelog-interviews": URL.valid(),
        "this-american-life-podcast": URL.valid(),
        "this-american-life-episode1": URL.valid(),
        "this-american-life-episode2": URL.valid(),
        "pod-save-america-podcast": URL.valid(),
        "pod-save-america-episode1": URL.valid(),
        "pod-save-america-episode2": URL.valid(),
      ]
      for (assetName, url) in imageMapping {
        dataLoader.respond(
          to: url,
          data: PreviewBundle.loadImageData(named: assetName, in: .EpisodeThumbnails)
        )
      }

      let basePodcast = try Create.unsavedPodcast(
        title: "PodHaven Complete Test",
        image: Array(imageMapping.values)[0],
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
            image: Array(imageMapping.values)[1]
          ),
          unsavedEpisode: try Create.unsavedEpisode(
            title: "2. Started Episode (progress in duration)",
            pubDate: Date().addingTimeInterval(-3600 * 24 * 2),
            image: Array(imageMapping.values)[3],  // Episode-specific image
            currentTime: CMTime.seconds(300)
          )
        ),
        UnsavedPodcastEpisode(
          unsavedPodcast: try Create.unsavedPodcast(
            title: "This American Life",
            image: Array(imageMapping.values)[2]
          ),
          unsavedEpisode: try Create.unsavedEpisode(
            title: "3. Finished Episode (blue checkmark) - SELECTED",
            pubDate: Date().addingTimeInterval(-3600 * 24 * 3),
            image: Array(imageMapping.values)[5],  // Episode-specific image
            completionDate: Date().addingTimeInterval(-3600 * 12)
          )
        ),
        UnsavedPodcastEpisode(
          unsavedPodcast: basePodcast,
          unsavedEpisode: try Create.unsavedEpisode(
            title: "4. Started + Finished - SELECTED",
            pubDate: Date().addingTimeInterval(-3600 * 24 * 4),
            image: Array(imageMapping.values)[4],  // Changelog Interviews image
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
            image: Array(imageMapping.values)[4]
          ),
          unsavedEpisode: try Create.unsavedEpisode(
            title: "5. Queued at Top (orange arrow up)",
            pubDate: Date().addingTimeInterval(-3600 * 24 * 5),
            image: Array(imageMapping.values)[6],  // Pod Save America episode image
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
            image: Array(imageMapping.values)[2]
          ),
          unsavedEpisode: try Create.unsavedEpisode(
            title: "7. Queued + Started",
            pubDate: Date().addingTimeInterval(-3600 * 24 * 7),
            image: Array(imageMapping.values)[7],  // This American Life episode image
            currentTime: CMTime.seconds(600),
            queueOrder: 3
          )
        ),
        UnsavedPodcastEpisode(
          unsavedPodcast: try Create.unsavedPodcast(
            title: "Pod Save America",
            image: Array(imageMapping.values)[1]
          ),
          unsavedEpisode: try Create.unsavedEpisode(
            title: "8. Queued + Finished",
            pubDate: Date().addingTimeInterval(-3600 * 24 * 8),
            image: Array(imageMapping.values)[3],  // Pod Save America episode image
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
            image: Array(imageMapping.values)[0]
          ),
          unsavedEpisode: try Create.unsavedEpisode(
            title: "9. Cached Episode (green download)",
            pubDate: Date().addingTimeInterval(-3600 * 24 * 9),
            image: Array(imageMapping.values)[4],  // Changelog Interviews
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
            image: Array(imageMapping.values)[2]
          ),
          unsavedEpisode: try Create.unsavedEpisode(
            title: "11. Cached + Finished",
            pubDate: Date().addingTimeInterval(-3600 * 24 * 11),
            image: Array(imageMapping.values)[5],  // This American Life episode
            completionDate: Date().addingTimeInterval(-3600 * 8),
            cachedFilename: "cached_finished.mp3"
          )
        ),
        UnsavedPodcastEpisode(
          unsavedPodcast: try Create.unsavedPodcast(
            title: "Pod Save America",
            image: Array(imageMapping.values)[1]
          ),
          unsavedEpisode: try Create.unsavedEpisode(
            title: "12. Cached + Queued",
            pubDate: Date().addingTimeInterval(-3600 * 24 * 12),
            image: Array(imageMapping.values)[6],  // Pod Save America episode 2
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
            image: Array(imageMapping.values)[0]
          ),
          unsavedEpisode: try Create.unsavedEpisode(
            title: "13. Caching: 25% Progress (green circle)",
            pubDate: Date().addingTimeInterval(-3600 * 24 * 13),
            image: Array(imageMapping.values)[4]  // Changelog Interviews
          )
        )
      )

      let cachingEpisode65 = try await repo.upsertPodcastEpisode(
        UnsavedPodcastEpisode(
          unsavedPodcast: try Create.unsavedPodcast(
            title: "Pod Save America",
            image: Array(imageMapping.values)[1]
          ),
          unsavedEpisode: try Create.unsavedEpisode(
            title: "14. Caching: 65% Progress (larger green circle)",
            pubDate: Date().addingTimeInterval(-3600 * 24 * 14),
            image: Array(imageMapping.values)[3]  // Pod Save America episode
          )
        )
      )

      let waitingEpisode = try await repo.upsertPodcastEpisode(
        UnsavedPodcastEpisode(
          unsavedPodcast: try Create.unsavedPodcast(
            title: "This American Life",
            image: Array(imageMapping.values)[2]
          ),
          unsavedEpisode: try Create.unsavedEpisode(
            title: "15. Caching: Waiting (green clock icon)",
            pubDate: Date().addingTimeInterval(-3600 * 24 * 15),
            image: Array(imageMapping.values)[7]  // This American Life episode 2
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
            image: Array(imageMapping.values)[0]
          ),
          unsavedEpisode: try Create.unsavedEpisode(
            title: "16. Everything: Queued + Cached + Started - SELECTED",
            pubDate: Date().addingTimeInterval(-3600 * 24 * 16),
            image: Array(imageMapping.values)[4],  // Changelog Interviews
            currentTime: CMTime.seconds(900),
            queueOrder: 1,
            cachedFilename: "everything.mp3"
          )
        ),
        UnsavedPodcastEpisode(
          unsavedPodcast: try Create.unsavedPodcast(
            title: "Pod Save America",
            image: Array(imageMapping.values)[1]
          ),
          unsavedEpisode: try Create.unsavedEpisode(
            title: "17. Top Queue + Cached + Finished",
            pubDate: Date().addingTimeInterval(-3600 * 24 * 17),
            image: Array(imageMapping.values)[3],  // Pod Save America episode
            completionDate: Date().addingTimeInterval(-3600 * 2),
            queueOrder: 0,
            cachedFilename: "top_queue_finished.mp3"
          )
        ),
        UnsavedPodcastEpisode(
          unsavedPodcast: try Create.unsavedPodcast(
            title: "This American Life",
            image: Array(imageMapping.values)[2]
          ),
          unsavedEpisode: try Create.unsavedEpisode(
            title: "18. All States: Queue + Cache + Complete + Started",
            pubDate: Date().addingTimeInterval(-3600 * 24 * 18),
            image: Array(imageMapping.values)[5],  // This American Life episode
            completionDate: Date().addingTimeInterval(-3600 * 1),
            currentTime: CMTime.seconds(1500),
            queueOrder: 4,
            cachedFilename: "all_states.mp3"
          )
        ),
        UnsavedPodcastEpisode(
          unsavedPodcast: try Create.unsavedPodcast(
            title: "Changelog Interviews",
            image: Array(imageMapping.values)[4]
          ),
          unsavedEpisode: try Create.unsavedEpisode(
            title: "19. Long Title to Test Layout with Multiple States and Icons - SELECTED",
            pubDate: Date().addingTimeInterval(-3600 * 24 * 19),
            image: Array(imageMapping.values)[6],  // Pod Save America episode 2
            currentTime: CMTime.seconds(2700),
            queueOrder: 8,
            cachedFilename: "long_title.mp3"
          )
        ),
      ])

      displayableEpisodes = episodes

      selectedStates = Array(repeating: false, count: episodes.count)
      // Set some episodes as selected for demonstration
      selectedStates[2] = true  // Finished episode
      selectedStates[3] = true  // Started + finished
      selectedStates[15] = true  // Everything episode
      selectedStates[18] = true  // Long title episode

    } catch {
      print("Error creating preview episodes: \(error)")
    }
  }
}
#endif
