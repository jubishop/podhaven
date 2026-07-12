// Copyright Justin Bishop, 2026

import AVFoundation
import FactoryKit
import FactoryTesting
import Foundation
import Testing

@testable import PodHaven

@Suite("of SharedState on-deck checks", .container)
@MainActor struct SharedStateOnDeckTests {
  @DynamicInjected(\.repo) private var repo
  @DynamicInjected(\.sharedState) private var sharedState

  // Regression: deleting a podcast flips its detail view to the unsaved
  // version, whose rows carry a nil episodeID. With nothing on deck, a raw
  // `onDeck?.id == episode.episodeID` check collapsed to `nil == nil`, lighting
  // the on-deck pause icon on every unsaved row.
  @Test("an unsaved episode is not on deck while nothing is on deck")
  func unsavedEpisodeIsNotOnDeckWhenNothingIsOnDeck() throws {
    let unsavedEpisode = UnsavedPodcastEpisode(
      unsavedPodcast: try Create.unsavedPodcast(),
      unsavedEpisode: try Create.unsavedEpisode(guid: "unsaved-1")
    )

    #expect(sharedState.onDeck == nil)
    #expect(!sharedState.isOnDeck(unsavedEpisode))
  }

  @Test("isOnDeck matches the on-deck saved episode but never an unsaved row")
  func isOnDeckMatchesSavedEpisodeOnly() async throws {
    let series = try await repo.insertSeries(
      UnsavedPodcastSeries(
        unsavedPodcast: try Create.unsavedPodcast(),
        unsavedEpisodes: [Create.unsavedEpisode(guid: "saved-1")]
      )
    )
    let episode = try #require(series.episodes.first)
    let podcastEpisode = PodcastEpisode(podcast: series.podcast, episode: episode)
    // `setOnDeck` sets both in production; identity checks read `currentEpisodeID`.
    sharedState.currentEpisodeID = podcastEpisode.id
    sharedState.$onDeck.new(OnDeck(from: podcastEpisode))

    let unsavedEpisode = UnsavedPodcastEpisode(
      unsavedPodcast: try Create.unsavedPodcast(),
      unsavedEpisode: try Create.unsavedEpisode(guid: "unsaved-1")
    )

    #expect(sharedState.isOnDeck(podcastEpisode))
    #expect(!sharedState.isOnDeck(unsavedEpisode))
  }

  // Regression: identity checks must not subscribe to the `onDeck` broadcast,
  // which playback rewrites as `currentTime` advances. Reading
  // `onDeck` for an identity-only check pulled every tick into the tracked
  // region of any view that only cares about which episode is current, so an
  // EpisodeDetailView with a long description rebuilt its body 4×/second while
  // anything played. `currentEpisodeID` moves only on episode transitions.
  @Test("identity checks ignore onDeck playback ticks but still wake on transitions")
  func identityChecksIgnoreOnDeckTicks() async throws {
    let series = try await repo.insertSeries(
      UnsavedPodcastSeries(
        unsavedPodcast: try Create.unsavedPodcast(),
        unsavedEpisodes: [Create.unsavedEpisode(guid: "saved-1")]
      )
    )
    let episode = try #require(series.episodes.first)
    let podcastEpisode = PodcastEpisode(podcast: series.podcast, episode: episode)

    sharedState.currentEpisodeID = podcastEpisode.id
    sharedState.$onDeck.new(OnDeck(from: podcastEpisode))
    sharedState.setPlaybackStatus(.playing)
    #expect(sharedState.isEpisodePlaying(podcastEpisode.id))

    let invalidated = ThreadSafe(false)
    withObservationTracking {
      _ = sharedState.isEpisodePlaying(podcastEpisode.id)
    } onChange: {
      invalidated(true)
    }

    // A playback tick mutates only `onDeck.currentTime`.
    sharedState.$onDeck.update { $0?.currentTime = CMTime.seconds(30) }
    #expect(!invalidated())

    // The same registration must still wake on a real play/pause transition.
    sharedState.setPlaybackStatus(.paused)
    #expect(invalidated())
  }
}
