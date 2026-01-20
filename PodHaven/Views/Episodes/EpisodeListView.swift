// Copyright Justin Bishop, 2025

import AVFoundation
import FactoryKit
import SwiftUI
import Tagged

struct EpisodeListView<Episode: EpisodeListable>: View {
  @DynamicInjected(\.userSettings) private var userSettings

  private let imageSize: CGFloat = 64

  private let episode: Episode
  private let alwaysShowPodcastImage: Bool
  private let isSelecting: Bool
  private let isSelected: Binding<Bool>

  init(
    episode: Episode,
    alwaysShowPodcastImage: Bool = false,
    isSelecting: Bool = false,
    isSelected: Binding<Bool> = .constant(false)
  ) {
    self.episode = episode
    self.alwaysShowPodcastImage = alwaysShowPodcastImage
    self.isSelecting = isSelecting
    self.isSelected = isSelected
  }

  var body: some View {
    HStack(alignment: .center, spacing: 4) {
      episodeImage
      StatusIconColumn(episode: episode, iconSpacing: 10, iconSize: 12)
      episodeInfoSection
    }
  }

  var episodeImage: some View {
    SquareImage(
      image: alwaysShowPodcastImage ? episode.podcastImage : episode.image,
      size: imageSize
    )
    .selectable(
      isSelecting: isSelecting,
      isSelected: isSelected
    )
  }

  var episodeInfoSection: some View {
    VStack(alignment: .leading) {
      HTMLText(episode.title)
        .font(.body)
        .lineLimit(2, reservesSpace: true)
        .multilineTextAlignment(.leading)
        .frame(maxWidth: .infinity, alignment: .topLeading)

      Spacer(minLength: 4)

      // Metadata Row
      HStack {
        CompactMetadataItem(appIcon: .publishDate, value: episode.pubDate.usShort)

        Spacer()

        CompactMetadataItem(appIcon: .duration, value: durationText)
      }
      .font(.footnote)
    }
    .frame(minHeight: imageSize)
    .fixedSize(horizontal: false, vertical: true)
  }

  // MARK: - Private Helpers

  private var durationText: String {
    userSettings.showTimeRemainingInEpisodeLists
      ? (episode.duration.safe - episode.currentTime.safe).shortDescription
      : episode.duration.safe.shortDescription
  }
}

// MARK: - Preview

#if DEBUG
#Preview("All Episode Status Icons & States") {
  @Previewable @State var displayedEpisodes: [DisplayedEpisode] = []
  @Previewable @State var selectedStates: [Bool] = []
  @Previewable @State var isSelected = BindableDictionary<MediaGUID, Bool>(defaultValue: false)

  NavigationStack {
    List {
      ForEach(Array(displayedEpisodes.enumerated()), id: \.element.mediaGUID) { index, episode in
        NavigationLink {
        } label: {
          EpisodeListView(
            episode: episode,
            isSelecting: selectedStates[safe: index] ?? false,
            isSelected: $isSelected[episode.mediaGUID]
          )
          .listRowSeparator()
        }
        .listRow()
      }
    }
  }
  .preview()
  .task {
    do {
      let sharedState = Container.shared.sharedState()
      let repo = Container.shared.repo()

      let allThumbnails = PreviewBundle.loadAllThumbnails()

      let basePodcast = try Create.unsavedPodcast(
        title: "PodHaven Complete Test",
        image: allThumbnails.randomElement()!.value.url,
        description: "Testing all episode status icon combinations"
      )

      var episodes: [any EpisodeDisplayable] = []

      // Basic States - UnsavedPodcastEpisodes
      episodes.append(contentsOf: [
        UnsavedPodcastEpisode(
          unsavedPodcast: basePodcast,
          unsavedEpisode: try Create.unsavedEpisode(
            title: "1. Default Episode (no icons) - Grey Box",
            pubDate: Date().addingTimeInterval(-3600 * 24 * 1),
            duration: CMTime.seconds(2400)
            // No image specified = uses basePodcast image (Changelog)
          )
        ),
        UnsavedPodcastEpisode(
          unsavedPodcast: try Create.unsavedPodcast(
            title: "Pod Save America",
            image: allThumbnails.randomElement()!.value.url
          ),
          unsavedEpisode: try Create.unsavedEpisode(
            title: "2. Started Episode (progress in duration)",
            pubDate: Date().addingTimeInterval(-3600 * 24 * 2),
            duration: CMTime.seconds(1800),
            image: allThumbnails.randomElement()!.value.url,  // Episode-specific image
            currentTime: CMTime.seconds(300)
          )
        ),
        UnsavedPodcastEpisode(
          unsavedPodcast: try Create.unsavedPodcast(
            title: "This American Life",
            image: allThumbnails.randomElement()!.value.url
          ),
          unsavedEpisode: try Create.unsavedEpisode(
            title: "3. Finished Episode (blue checkmark) - SELECTED",
            pubDate: Date().addingTimeInterval(-3600 * 24 * 3),
            duration: CMTime.seconds(2700),
            image: allThumbnails.randomElement()!.value.url,  // Episode-specific image
            finishDate: Date().addingTimeInterval(-3600 * 12)
          )
        ),
        UnsavedPodcastEpisode(
          unsavedPodcast: basePodcast,
          unsavedEpisode: try Create.unsavedEpisode(
            title: "4. Started + Finished - SELECTED",
            pubDate: Date().addingTimeInterval(-3600 * 24 * 4),
            duration: CMTime.seconds(3600),
            image: allThumbnails.randomElement()!.value.url,  // Changelog Interviews image
            finishDate: Date().addingTimeInterval(-3600 * 6),
            currentTime: CMTime.seconds(1800)
          )
        ),
      ])

      // Queue States - UnsavedPodcastEpisodes
      episodes.append(contentsOf: [
        UnsavedPodcastEpisode(
          unsavedPodcast: try Create.unsavedPodcast(
            title: "Changelog Interviews",
            image: allThumbnails.randomElement()!.value.url
          ),
          unsavedEpisode: try Create.unsavedEpisode(
            title: "5. Queued at Top (orange arrow up)",
            pubDate: Date().addingTimeInterval(-3600 * 24 * 5),
            duration: CMTime.seconds(2100),
            image: allThumbnails.randomElement()!.value.url,  // Pod Save America episode image
            queueOrder: 0
          )
        ),
        UnsavedPodcastEpisode(
          unsavedPodcast: basePodcast,  // Grey box - invalid image
          unsavedEpisode: try Create.unsavedEpisode(
            title: "6. Queued Middle (orange lines) - Grey Box",
            pubDate: Date().addingTimeInterval(-3600 * 24 * 6),
            duration: CMTime.seconds(900),
            image: nil,  // Will show grey box
            queueOrder: 5
          )
        ),
        UnsavedPodcastEpisode(
          unsavedPodcast: try Create.unsavedPodcast(
            title: "This American Life",
            image: allThumbnails.randomElement()!.value.url
          ),
          unsavedEpisode: try Create.unsavedEpisode(
            title: "7. Queued + Started",
            pubDate: Date().addingTimeInterval(-3600 * 24 * 7),
            duration: CMTime.seconds(2400),
            image: allThumbnails.randomElement()!.value.url,  // This American Life episode image
            currentTime: CMTime.seconds(600),
            queueOrder: 3
          )
        ),
        UnsavedPodcastEpisode(
          unsavedPodcast: try Create.unsavedPodcast(
            title: "Pod Save America",
            image: allThumbnails.randomElement()!.value.url
          ),
          unsavedEpisode: try Create.unsavedEpisode(
            title: "8. Queued + Finished",
            pubDate: Date().addingTimeInterval(-3600 * 24 * 8),
            duration: CMTime.seconds(3000),
            image: allThumbnails.randomElement()!.value.url,  // Pod Save America episode image
            finishDate: Date().addingTimeInterval(-3600 * 3),
            queueOrder: 2
          )
        ),
      ])

      // Cache States - UnsavedPodcastEpisodes
      episodes.append(contentsOf: [
        UnsavedPodcastEpisode(
          unsavedPodcast: try Create.unsavedPodcast(
            title: "Changelog",
            image: allThumbnails.randomElement()!.value.url
          ),
          unsavedEpisode: try Create.unsavedEpisode(
            title: "9. Cached Episode (green download)",
            pubDate: Date().addingTimeInterval(-3600 * 24 * 9),
            duration: CMTime.seconds(3300),
            image: allThumbnails.randomElement()!.value.url,  // Changelog Interviews
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
            duration: CMTime.seconds(1800),
            currentTime: CMTime.seconds(450),
            cachedFilename: "cached_started.mp3"
              // No episode image = falls back to podcast image (grey box)
          )
        ),
        UnsavedPodcastEpisode(
          unsavedPodcast: try Create.unsavedPodcast(
            title: "This American Life",
            image: allThumbnails.randomElement()!.value.url
          ),
          unsavedEpisode: try Create.unsavedEpisode(
            title: "11. Cached + Finished",
            pubDate: Date().addingTimeInterval(-3600 * 24 * 11),
            duration: CMTime.seconds(2600),
            image: allThumbnails.randomElement()!.value.url,  // This American Life episode
            finishDate: Date().addingTimeInterval(-3600 * 8),
            cachedFilename: "cached_finished.mp3"
          )
        ),
        UnsavedPodcastEpisode(
          unsavedPodcast: try Create.unsavedPodcast(
            title: "Pod Save America",
            image: allThumbnails.randomElement()!.value.url
          ),
          unsavedEpisode: try Create.unsavedEpisode(
            title: "12. Cached + Queued",
            pubDate: Date().addingTimeInterval(-3600 * 24 * 12),
            duration: CMTime.seconds(4000),
            image: allThumbnails.randomElement()!.value.url,  // Pod Save America episode 2
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
            image: allThumbnails.randomElement()!.value.url
          ),
          unsavedEpisode: try Create.unsavedEpisode(
            title: "13. Caching: 25% Progress (green circle)",
            pubDate: Date().addingTimeInterval(-3600 * 24 * 13),
            duration: CMTime.seconds(3600),
            image: allThumbnails.randomElement()!.value.url  // Changelog Interviews
          )
        )
      )

      let cachingEpisode65 = try await repo.upsertPodcastEpisode(
        UnsavedPodcastEpisode(
          unsavedPodcast: try Create.unsavedPodcast(
            title: "Pod Save America",
            image: allThumbnails.randomElement()!.value.url
          ),
          unsavedEpisode: try Create.unsavedEpisode(
            title: "14. Caching: 65% Progress (larger green circle)",
            pubDate: Date().addingTimeInterval(-3600 * 24 * 14),
            duration: CMTime.seconds(3000),
            image: allThumbnails.randomElement()!.value.url  // Pod Save America episode
          )
        )
      )

      let waitingEpisode = try await repo.upsertPodcastEpisode(
        UnsavedPodcastEpisode(
          unsavedPodcast: try Create.unsavedPodcast(
            title: "This American Life",
            image: allThumbnails.randomElement()!.value.url
          ),
          unsavedEpisode: try Create.unsavedEpisode(
            title: "15. Caching: Waiting (green clock icon)",
            pubDate: Date().addingTimeInterval(-3600 * 24 * 15),
            duration: CMTime.seconds(1500),
            image: allThumbnails.randomElement()!.value.url  // This American Life episode 2
          )
        )
      )

      // Set up caching states for progress episodes
      try await repo.updateDownloadTaskID(
        cachingEpisode25.id,
        downloadTaskID: URLSessionDownloadTask.ID(exactly: cachingEpisode25.id.rawValue)
      )
      try await repo.updateDownloadTaskID(
        cachingEpisode65.id,
        downloadTaskID: URLSessionDownloadTask.ID(exactly: cachingEpisode65.id.rawValue)
      )
      try await repo.updateDownloadTaskID(
        waitingEpisode.id,
        downloadTaskID: URLSessionDownloadTask.ID(exactly: waitingEpisode.id.rawValue)
      )

      // Simulate cache progress
      sharedState.updateDownloadProgress(for: cachingEpisode25.id, progress: 0.25)
      sharedState.updateDownloadProgress(for: cachingEpisode65.id, progress: 0.65)
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
            image: allThumbnails.randomElement()!.value.url
          ),
          unsavedEpisode: try Create.unsavedEpisode(
            title: "16. Everything: Queued + Cached + Started - SELECTED",
            pubDate: Date().addingTimeInterval(-3600 * 24 * 16),
            duration: CMTime.seconds(3600),
            image: allThumbnails.randomElement()!.value.url,  // Changelog Interviews
            currentTime: CMTime.seconds(900),
            queueOrder: 1,
            cachedFilename: "everything.mp3"
          )
        ),
        UnsavedPodcastEpisode(
          unsavedPodcast: try Create.unsavedPodcast(
            title: "Pod Save America",
            image: allThumbnails.randomElement()!.value.url
          ),
          unsavedEpisode: try Create.unsavedEpisode(
            title: "17. Top Queue + Cached + Finished",
            pubDate: Date().addingTimeInterval(-3600 * 24 * 17),
            duration: CMTime.seconds(2700),
            image: allThumbnails.randomElement()!.value.url,  // Pod Save America episode
            finishDate: Date().addingTimeInterval(-3600 * 2),
            queueOrder: 0,
            cachedFilename: "top_queue_finished.mp3"
          )
        ),
        UnsavedPodcastEpisode(
          unsavedPodcast: try Create.unsavedPodcast(
            title: "This American Life",
            image: allThumbnails.randomElement()!.value.url
          ),
          unsavedEpisode: try Create.unsavedEpisode(
            title: "18. All States: Queue + Cache + Complete + Started",
            pubDate: Date().addingTimeInterval(-3600 * 24 * 18),
            duration: CMTime.seconds(4200),
            image: allThumbnails.randomElement()!.value.url,  // This American Life episode
            finishDate: Date().addingTimeInterval(-3600 * 1),
            currentTime: CMTime.seconds(1500),
            queueOrder: 4,
            cachedFilename: "all_states.mp3"
          )
        ),
        UnsavedPodcastEpisode(
          unsavedPodcast: try Create.unsavedPodcast(
            title: "Changelog Interviews",
            image: allThumbnails.randomElement()!.value.url
          ),
          unsavedEpisode: try Create.unsavedEpisode(
            title: "19. Long Title to Test Layout with Multiple States and Icons - SELECTED",
            pubDate: Date().addingTimeInterval(-3600 * 24 * 19),
            duration: CMTime.seconds(5400),
            image: allThumbnails.randomElement()!.value.url,  // Pod Save America episode 2
            currentTime: CMTime.seconds(2700),
            queueOrder: 8,
            cachedFilename: "long_title.mp3"
          )
        ),
      ])

      displayedEpisodes = episodes.map { DisplayedEpisode.getDisplayedEpisode($0) }

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
