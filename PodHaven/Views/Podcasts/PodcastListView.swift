// Copyright Justin Bishop, 2025

import Foundation
import SwiftUI

struct PodcastListView<Podcast: PodcastDisplayable>: View {
  private let imageSize: CGFloat = 76

  private let podcastWithMetadata: PodcastWithEpisodeMetadata<Podcast>
  private let isSelecting: Bool
  private let isSelected: Binding<Bool>

  init(
    podcastWithMetadata: PodcastWithEpisodeMetadata<Podcast>,
    isSelecting: Bool = false,
    isSelected: Binding<Bool> = .constant(false)
  ) {
    self.podcastWithMetadata = podcastWithMetadata
    self.isSelecting = isSelecting
    self.isSelected = isSelected
  }

  var body: some View {
    HStack(alignment: .center, spacing: 12) {
      podcastImage
      podcastInfoSection
    }
  }

  var podcastImage: some View {
    SquareImage(
      image: podcastWithMetadata.image,
      size: imageSize
    )
    .selectable(
      isSelecting: isSelecting,
      isSelected: isSelected
    )
    .subscriptionBadge(
      subscribed: podcastWithMetadata.subscribed,
      badgeSize: 12
    )
  }

  var podcastInfoSection: some View {
    VStack(alignment: .leading) {
      Text(podcastWithMetadata.title)
        .font(.body)
        .lineLimit(2, reservesSpace: true)
        .multilineTextAlignment(.leading)
        .frame(maxWidth: .infinity, alignment: .topLeading)

      Spacer(minLength: 4)

      // Metadata Row
      HStack {
        if let mostRecentEpisodeDate = podcastWithMetadata.mostRecentEpisodeDate {
          CompactMetadataItem(appIcon: .publishDate, value: mostRecentEpisodeDate.usShort)
        }

        Spacer()

        CompactMetadataItem(appIcon: .episodeCount, value: "\(podcastWithMetadata.episodeCount) Ep")
      }
      .font(.footnote)
    }
    .frame(minHeight: imageSize)
  }
}

// MARK: - Preview

#if DEBUG
#Preview("All Podcast States") {
  @Previewable @State var displayedPodcasts: [PodcastWithEpisodeMetadata<UnsavedPodcast>] = []
  @Previewable @State var selectedStates: [Bool] = []
  @Previewable @State var isSelected = BindableDictionary<FeedURL, Bool>(defaultValue: false)

  NavigationStack {
    List {
      ForEach(Array(displayedPodcasts.enumerated()), id: \.element.feedURL) { index, podcast in
        NavigationLink {
        } label: {
          PodcastListView(
            podcastWithMetadata: podcast,
            isSelecting: selectedStates[safe: index] ?? false,
            isSelected: $isSelected[podcast.feedURL]
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
      let allThumbnails = PreviewBundle.loadAllThumbnails()
      var podcasts: [PodcastWithEpisodeMetadata<UnsavedPodcast>] = []

      // Basic States - No subscription, various episode counts
      podcasts.append(contentsOf: [
        PodcastWithEpisodeMetadata(
          podcast: try Create.unsavedPodcast(
            title: "1. Basic Podcast (no subscription)",
            image: allThumbnails.randomElement()!.value.url,
            description: "A podcast without subscription status"
          ),
          episodeCount: 42,
          mostRecentEpisodeDate: Date().addingTimeInterval(-3600 * 24 * 1)
        ),
        PodcastWithEpisodeMetadata(
          podcast: try Create.unsavedPodcast(
            title: "2. Subscribed Podcast (badge overlay)",
            image: allThumbnails.randomElement()!.value.url,
            description: "A subscribed podcast with badge",
            subscriptionDate: Date().addingTimeInterval(-3600 * 24 * 30)
          ),
          episodeCount: 128,
          mostRecentEpisodeDate: Date().addingTimeInterval(-3600 * 24 * 2)
        ),
        PodcastWithEpisodeMetadata(
          podcast: try Create.unsavedPodcast(
            title: "3. Few Episodes (single digit) - SELECTED",
            image: allThumbnails.randomElement()!.value.url,
            description: "A new podcast with few episodes"
          ),
          episodeCount: 5,
          mostRecentEpisodeDate: Date().addingTimeInterval(-3600 * 24 * 3)
        ),
        PodcastWithEpisodeMetadata(
          podcast: try Create.unsavedPodcast(
            title: "4. High Episode Count (3 digits) - SELECTED",
            image: allThumbnails.randomElement()!.value.url,
            description: "Long-running podcast",
            subscriptionDate: Date().addingTimeInterval(-3600 * 24 * 60)
          ),
          episodeCount: 456,
          mostRecentEpisodeDate: Date().addingTimeInterval(-3600 * 24 * 7)
        ),
      ])

      // Various Recent Episode Dates
      podcasts.append(contentsOf: [
        PodcastWithEpisodeMetadata(
          podcast: try Create.unsavedPodcast(
            title: "5. Recent Episode (today)",
            image: allThumbnails.randomElement()!.value.url,
            description: "Just published today",
            subscriptionDate: Date().addingTimeInterval(-3600 * 24 * 7)
          ),
          episodeCount: 89,
          mostRecentEpisodeDate: Date()
        ),
        PodcastWithEpisodeMetadata(
          podcast: try Create.unsavedPodcast(
            title: "6. Old Episode (months ago) - Grey Box",
            image: URL.valid(),  // Grey box
            description: "Inactive podcast"
          ),
          episodeCount: 32,
          mostRecentEpisodeDate: Date().addingTimeInterval(-3600 * 24 * 90)
        ),
        PodcastWithEpisodeMetadata(
          podcast: try Create.unsavedPodcast(
            title: "7. No Recent Episode Date - SELECTED",
            image: allThumbnails.randomElement()!.value.url,
            description: "No episode metadata available",
            subscriptionDate: Date().addingTimeInterval(-3600 * 24 * 90)
          ),
          episodeCount: 15,
          mostRecentEpisodeDate: nil
        ),
      ])

      // Image States
      podcasts.append(contentsOf: [
        PodcastWithEpisodeMetadata(
          podcast: try Create.unsavedPodcast(
            title: "8. Grey Box (invalid image)",
            image: URL.valid(),
            description: "Invalid image URL"
          ),
          episodeCount: 67,
          mostRecentEpisodeDate: Date().addingTimeInterval(-3600 * 24 * 14)
        ),
        PodcastWithEpisodeMetadata(
          podcast: try Create.unsavedPodcast(
            title: "9. Valid Image + Subscribed - SELECTED",
            image: allThumbnails.randomElement()!.value.url,
            description: "Good image with subscription",
            subscriptionDate: Date().addingTimeInterval(-3600 * 24 * 14)
          ),
          episodeCount: 234,
          mostRecentEpisodeDate: Date().addingTimeInterval(-3600 * 24 * 5)
        ),
      ])

      // Title Length Tests
      podcasts.append(contentsOf: [
        PodcastWithEpisodeMetadata(
          podcast: try Create.unsavedPodcast(
            title:
              "10. Very Long Title That Should Be Truncated to Two Lines Maximum When Displayed in the List View",
            image: allThumbnails.randomElement()!.value.url,
            description: "Testing long title layout"
          ),
          episodeCount: 99,
          mostRecentEpisodeDate: Date().addingTimeInterval(-3600 * 24 * 4)
        ),
        PodcastWithEpisodeMetadata(
          podcast: try Create.unsavedPodcast(
            title: "11. Short",
            image: allThumbnails.randomElement()!.value.url,
            description: "Testing short title",
            subscriptionDate: Date().addingTimeInterval(-3600 * 24 * 3)
          ),
          episodeCount: 12,
          mostRecentEpisodeDate: Date().addingTimeInterval(-3600 * 24 * 1)
        ),
      ])

      // Edge Cases
      podcasts.append(contentsOf: [
        PodcastWithEpisodeMetadata(
          podcast: try Create.unsavedPodcast(
            title: "12. Zero Episodes (edge case)",
            image: allThumbnails.randomElement()!.value.url,
            description: "Podcast with no episodes"
          ),
          episodeCount: 0,
          mostRecentEpisodeDate: nil
        ),
        PodcastWithEpisodeMetadata(
          podcast: try Create.unsavedPodcast(
            title: "13. Max Episode Count",
            image: allThumbnails.randomElement()!.value.url,
            description: "Very prolific podcast",
            subscriptionDate: Date().addingTimeInterval(-3600 * 24 * 120)
          ),
          episodeCount: 9999,
          mostRecentEpisodeDate: Date().addingTimeInterval(-3600 * 2)
        ),
        PodcastWithEpisodeMetadata(
          podcast: try Create.unsavedPodcast(
            title: "14. All States: Subscribed + Old + Many Episodes - SELECTED",
            image: allThumbnails.randomElement()!.value.url,
            description: "Combination of all states",
            subscriptionDate: Date().addingTimeInterval(-3600 * 24 * 200)
          ),
          episodeCount: 543,
          mostRecentEpisodeDate: Date().addingTimeInterval(-3600 * 24 * 180)
        ),
      ])

      displayedPodcasts = podcasts

      selectedStates = Array(repeating: false, count: podcasts.count)
      // Set some podcasts as selected for demonstration
      selectedStates[2] = true  // Few episodes
      selectedStates[3] = true  // High episode count
      selectedStates[6] = true  // No recent date
      selectedStates[8] = true  // Valid image + subscribed
      selectedStates[13] = true  // All states

    } catch {
      print("Error creating preview podcasts: \(error)")
    }
  }
}
#endif
